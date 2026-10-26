import Foundation

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
/// Uses the OAuth App client id that VS Code / the Copilot extension ships with,
/// so the resulting `gho_…` token has access to the Copilot quota API.
/// Same flow as CodexBar's Copilot provider (client id `Iv1.b507a08c87ecfe98`, scope `read:user`).
struct GitHubDeviceFlow {
    static let clientID = "Iv1.b507a08c87ecfe98"
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
        case success(String)
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
    func waitForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> String {
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DeviceFlowError.network
        }

        struct RawTokenResponse: Decodable {
            let accessToken: String?
            let error: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case error
            }
        }

        let raw = try JSONDecoder().decode(RawTokenResponse.self, from: data)
        if let token = raw.accessToken, !token.isEmpty {
            return .success(token)
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

    private func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8) ?? Data()
    }
}
