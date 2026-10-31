import Foundation
import os

private let tokenLog = Logger(subsystem: "com.addo.copilotquota", category: "token")

enum DeviceFlowError: LocalizedError {
    case network
    case denied
    case expired
    case api(String)

    var errorDescription: String? {
        switch self {
        case .network:
            return L("Network request failed. Please try again.")
        case .denied:
            return L("You denied the authorization request.")
        case .expired:
            return L("The device code has expired. Please sign in again.")
        case .api(let message):
            return L("GitHub authorization failed: %@", message)
        }
    }
}

/// GitHub OAuth Device Flow.
///
/// Uses this project's own OAuth App ("CopilotQuota", Device Flow enabled),
/// so tokens live in their own authorization bucket — re-authorizing other
/// Copilot tools (or this app) does not revoke them, and vice versa.
/// OAuth app tokens carry `read:user` scope; no client secret is needed for
/// the device flow.
struct GitHubDeviceFlow {
    static let clientID = "Ov23likPMhK9KRRdi42k"
    private let scope = "read:user"

    private let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    private let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    struct DeviceCodeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let verificationUriComplete: String?
        let expiresIn: Int
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case verificationUriComplete = "verification_uri_complete"
            case expiresIn = "expires_in"
            case interval
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            deviceCode = try c.decode(String.self, forKey: .deviceCode)
            userCode = try c.decode(String.self, forKey: .userCode)
            verificationUri = try c.decode(String.self, forKey: .verificationUri)
            verificationUriComplete = try c.decodeIfPresent(String.self, forKey: .verificationUriComplete)
            expiresIn = try c.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 900
            interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? 5
        }
    }

    enum PollResult {
        case pending
        case slowDown
        case success(TokenPair)
    }

    /// A token exchange result: access token plus the rotating refresh token
    /// and its lifetime. GitHub App user-to-server access tokens expire after
    /// 8 hours; refresh tokens after 6 months and are ROTATED on every use.
    struct TokenPair {
        let accessToken: String
        let refreshToken: String?
        let expiresInSeconds: Int
    }

    /// Decodes the shared shape of both the device-flow poll and the
    /// refresh-token grant responses.
    private struct RawTokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresInSeconds: Int?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresInSeconds = "expires_in"
            case error
        }

        var pair: TokenPair? {
            guard let accessToken, !accessToken.isEmpty else { return nil }
            // A refresh token means the app is set to expire access tokens
            // (~8h, renewable). Without one the token is non-expiring —
            // don't invent a default expiry or validToken() would churn on a
            // token that can never be refreshed.
            let expiry: Int
            if refreshToken != nil {
                expiry = expiresInSeconds ?? 8 * 3600
            } else {
                expiry = expiresInSeconds ?? 100 * 365 * 24 * 3600 // non-expiring
            }
            return TokenPair(accessToken: accessToken,
                             refreshToken: refreshToken,
                             expiresInSeconds: expiry)
        }
    }

    /// Step 1: ask GitHub for a device + user code.
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: deviceCodeURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": Self.clientID,
            "scope": scope,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DeviceFlowError.network
        }
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    /// Step 2: poll until the user finishes the browser flow.
    func waitForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> TokenPair {
        let deadline = Date().addingTimeInterval(TimeInterval(max(60, expiresIn)))
        var step = TimeInterval(max(1, interval))
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            try Task.checkCancellation()
            switch try await pollTokenOnce(deviceCode: deviceCode) {
            case .pending:
                continue
            case .slowDown:
                step += 5 // RFC 8628: increase interval by 5s on slow_down
            case .success(let token):
                return token
            }
        }
        throw DeviceFlowError.expired
    }

    func pollTokenOnce(deviceCode: String) async throws -> PollResult {
        var request = URLRequest(url: accessTokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": Self.clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])

        let (data, _) = try await URLSession.shared.data(for: request)

        let raw = try JSONDecoder().decode(RawTokenResponse.self, from: data)
        if let pair = raw.pair {
            return .success(pair)
        }
        switch raw.error {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown
        case "access_denied":
            throw DeviceFlowError.denied
        case "expired_token":
            throw DeviceFlowError.expired
        case .some(let other):
            throw DeviceFlowError.api(other)
        case .none:
            throw DeviceFlowError.network
        }
    }

    /// Refresh grant: exchange the (rotating) refresh token for a fresh pair.
    /// MUST be called only from a context that can persist the result
    /// (the host app) — GitHub invalidates the old refresh token on use.
    func refreshTokens(refreshToken: String) async throws -> TokenPair {
        var request = URLRequest(url: accessTokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let raw = try JSONDecoder().decode(RawTokenResponse.self, from: data)
        if let pair = raw.pair {
            return pair
        }
        // `invalid_grant` etc. — the refresh token expired/revoked; re-login.
        throw DeviceFlowError.api(raw.error ?? "unexpected empty token response")
    }

    private func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8) ?? Data()
    }
}

// MARK: - TokenManager

/// Token lifecycle, shared by the host app and the widget.
///
/// GitHub's refresh token ROTATES on every use — the response carries a new
/// pair and the old refresh token dies instantly. Since both the app and the
/// widget can reach the ~8h token expiry while the other is mid-refresh, all
/// rotations go through `validToken`'s race protocol:
///
/// 1. Normally only one side rotates at a time: the app advertises liveness
///    via `SharedStore.appHeartbeat`, and the widget only rotates when that
///    heartbeat has gone stale (app not running).
/// 2. If a race slips through anyway (e.g. the app launches exactly while
///    the widget is rotating), the loser's refresh call fails — it then
///    re-reads the stored refresh token ONCE and retries with the rotated
///    value before concluding the token is actually dead.
/// 3. Only `mayClearCredentials` callers (the host app) ever sign the user
///    out; the widget just falls back to its cache and lets the app decide.
enum TokenManager {
    /// Refresh this early before the actual expiry. Generous (1h) on
    /// purpose: the widget's timeline reloads are budget-spaced 15–60 min
    /// apart, so a small margin would let the ~8h token die between
    /// reloads. Rotating early costs nothing — it is still one rotation
    /// per ~8h, just scheduled before the cliff instead of after it.
    private static let refreshMargin: TimeInterval = 60 * 60

    enum Error: LocalizedError {
        case signedOut

        var errorDescription: String? {
            switch self {
            case .signedOut:
                return L("GitHub token is invalid or expired (401). Please sign in again.")
            }
        }
    }

    /// Returns a usable access token, refreshing first when needed.
    ///
    /// - When `forceRefresh` is false: refreshes only if the stored expiry is
    ///   missing or within `refreshMargin`. If there is no refresh token
    ///   (a legacy login from before auto-refresh existed), the possibly-stale
    ///   access token is returned as-is and the caller's 401 path recovers.
    /// - `mayClearCredentials`: pass false from the widget — a dead refresh
    ///   token there must NOT sign the user out of the app.
    /// - Throws `QuotaError.unauthorized` when the refresh token itself is
    ///   dead — in that case (app-side) credentials are cleared and the user
    ///   must re-authorize (refresh tokens live ~6 months).
    static func validToken(forceRefresh: Bool = false,
                           mayClearCredentials: Bool = true) async throws -> String {
        guard let storedToken = SharedStore.token else { throw Error.signedOut }

        let needsRefresh: Bool
        if forceRefresh {
            needsRefresh = true
        } else if let expiresAt = SharedStore.tokenExpiresAt {
            needsRefresh = expiresAt <= Date().addingTimeInterval(refreshMargin)
        } else {
            needsRefresh = false // legacy login without recorded expiry
        }

        guard needsRefresh, let refreshToken = SharedStore.refreshToken else {
            return storedToken
        }

        do {
            let token = try await rotate(refreshToken: refreshToken)
            tokenLog.info("token rotated, new access token valid ~\(8 * 3600, privacy: .public)s")
            return token
        } catch {
            // Rotation race: the other process may have consumed and rotated
            // this exact refresh token between our read and GitHub's
            // response. Re-read once and retry with whatever is stored now
            // before declaring the token dead.
            let latest = SharedStore.refreshToken
            if let latest, latest != refreshToken {
                tokenLog.info("rotation raced — retrying with re-read refresh token")
                if let token = try? await rotate(refreshToken: latest) {
                    return token
                }
            }
            if mayClearCredentials {
                tokenLog.error("refresh token dead — clearing credentials, sign-in required")
                SharedStore.clearCredentials() // truly dead — force re-login
            } else {
                tokenLog.error("refresh token dead (widget side) — falling back to cache")
            }
            throw QuotaError.unauthorized
        }
    }

    /// One refresh-grant round trip, persisting the rotated pair.
    private static func rotate(refreshToken: String) async throws -> String {
        let pair = try await GitHubDeviceFlow().refreshTokens(refreshToken: refreshToken)
        SharedStore.storeTokenPair(accessToken: pair.accessToken,
                                   refreshToken: pair.refreshToken,
                                   expiresInSeconds: pair.expiresInSeconds)
        return pair.accessToken
    }

    /// Fetch the quota with automatic token refresh and one 401 retry.
    /// (Host app only — the widget calls validToken/fetch directly and does
    /// NOT force-refresh on 401, to avoid rotation churn against the app.)
    static func fetchQuota() async throws -> CopilotUserResponse {
        let client = CopilotQuotaClient()
        let token = try await validToken()
        do {
            return try await client.fetch(token: token)
        } catch QuotaError.unauthorized {
            // Token was rejected early (revoked / clock skew): force one
            // refresh and retry before giving up.
            let freshToken = try await validToken(forceRefresh: true)
            return try await client.fetch(token: freshToken)
        }
    }
}
