import XCTest

final class TokenManagerAndStoreTests: XCTestCase {
    private var suiteName: String!
    private var legacySuiteName: String!
    private var defaults: UserDefaults!
    private var legacyDefaults: UserDefaults!
    private var keychain: InMemoryCredentialStore!

    override func setUp() {
        super.setUp()
        suiteName = "app.solocraft.copilotquota.tests.\(UUID().uuidString)"
        legacySuiteName = "com.addo.copilotquota.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        keychain = InMemoryCredentialStore()
        SharedStore.configureForTesting(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            credentialStore: keychain
        )
    }

    override func tearDown() {
        SharedStore.resetToProduction()
        defaults.removePersistentDomain(forName: suiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        super.tearDown()
    }

    func testMigratesPlaintextCredentialsToKeychainAndScrubsDefaults() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set("ghu_legacy_token", forKey: "githubToken")
        defaults.set("ghr_legacy_refresh", forKey: "githubRefreshToken")
        defaults.set(expiry, forKey: "githubTokenExpiresAt")

        XCTAssertEqual(SharedStore.token, "ghu_legacy_token")
        XCTAssertEqual(SharedStore.refreshToken, "ghr_legacy_refresh")
        XCTAssertEqual(SharedStore.tokenExpiresAt, expiry)

        // Keychain received the credentials and plaintext keys were scrubbed.
        XCTAssertEqual(keychain.load()?.accessToken, "ghu_legacy_token")
        XCTAssertNil(defaults.object(forKey: "githubToken"))
        XCTAssertNil(defaults.object(forKey: "githubRefreshToken"))
        XCTAssertNil(defaults.object(forKey: "githubTokenExpiresAt"))
    }

    func testValidTokenSkipsRefreshWhenNotNearExpiry() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        SharedStore.storeTokenPair(
            accessToken: "ghu_fresh",
            refreshToken: "ghr_1",
            expiresInSeconds: 8 * 3600,
            now: now
        )

        var refreshCalled = false
        let token = try await TokenManager.validToken(now: now.addingTimeInterval(3600)) { _ in
            refreshCalled = true
            return GitHubDeviceFlow.TokenPair(accessToken: "unexpected", refreshToken: "unexpected", expiresInSeconds: 3600)
        }
        XCTAssertEqual(token, "ghu_fresh")
        XCTAssertFalse(refreshCalled)
    }

    func testValidTokenRotatesWhenWithinRefreshMargin() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        SharedStore.storeTokenPair(
            accessToken: "ghu_old",
            refreshToken: "ghr_old",
            expiresInSeconds: 30 * 60, // within 1h margin
            now: now
        )

        let token = try await TokenManager.validToken(now: now) { receivedRefresh in
            XCTAssertEqual(receivedRefresh, "ghr_old")
            return GitHubDeviceFlow.TokenPair(
                accessToken: "ghu_new",
                refreshToken: "ghr_new",
                expiresInSeconds: 8 * 3600
            )
        }

        XCTAssertEqual(token, "ghu_new")
        XCTAssertEqual(SharedStore.token, "ghu_new")
        XCTAssertEqual(SharedStore.refreshToken, "ghr_new")
    }

    func testValidTokenRecoversFromRotationRace() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        SharedStore.storeTokenPair(
            accessToken: "ghu_old",
            refreshToken: "ghr_v1",
            expiresInSeconds: 60,
            now: now
        )

        var attempts: [String] = []
        let token = try await TokenManager.validToken(now: now) { refreshToken in
            attempts.append(refreshToken)
            if refreshToken == "ghr_v1" {
                // Simulate another process rotating the refresh token concurrently.
                SharedStore.storeTokenPair(
                    accessToken: "ghu_other",
                    refreshToken: "ghr_v2",
                    expiresInSeconds: 8 * 3600,
                    now: now
                )
                throw DeviceFlowError.api("invalid_grant")
            }
            return GitHubDeviceFlow.TokenPair(
                accessToken: "ghu_v3",
                refreshToken: "ghr_v3",
                expiresInSeconds: 8 * 3600
            )
        }

        XCTAssertEqual(attempts, ["ghr_v1", "ghr_v2"])
        XCTAssertEqual(token, "ghu_v3")
        XCTAssertEqual(SharedStore.refreshToken, "ghr_v3")
    }

    func testDeadRefreshTokenClearsCredentialsOnlyWhenAllowed() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        SharedStore.storeTokenPair(
            accessToken: "ghu_old",
            refreshToken: "ghr_dead",
            expiresInSeconds: 60,
            now: now
        )

        // Widget side (`mayClearCredentials: false`) must NOT sign out the host app.
        do {
            _ = try await TokenManager.validToken(mayClearCredentials: false, now: now) { _ in
                throw DeviceFlowError.api("invalid_grant")
            }
            XCTFail("Expected unauthorized error")
        } catch QuotaError.unauthorized {
            XCTAssertEqual(SharedStore.token, "ghu_old")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Host app side (`mayClearCredentials: true`) clears credentials.
        do {
            _ = try await TokenManager.validToken(mayClearCredentials: true, now: now) { _ in
                throw DeviceFlowError.api("invalid_grant")
            }
            XCTFail("Expected unauthorized error")
        } catch QuotaError.unauthorized {
            XCTAssertNil(SharedStore.token)
            XCTAssertNil(SharedStore.refreshToken)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
