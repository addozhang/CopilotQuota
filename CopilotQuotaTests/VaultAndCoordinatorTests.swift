import XCTest

private struct StubProvider: QuotaProvider {
    let kind: ProviderKind
    let handler: @Sendable (ProviderAccount) async throws -> ProviderSnapshot

    func fetchSnapshot(account: ProviderAccount, vault: CredentialVaulting) async throws -> ProviderSnapshot {
        try await handler(account)
    }
}

final class VaultAndCoordinatorTests: XCTestCase {
    private var suiteName: String!
    private var legacySuiteName: String!
    private var defaults: UserDefaults!
    private var legacyDefaults: UserDefaults!
    private var store: SharedSnapshotStore!
    private var vault: InMemoryCredentialVault!

    override func setUp() {
        super.setUp()
        suiteName = "app.solocraft.quotaring.tests.\(UUID().uuidString)"
        legacySuiteName = "app.solocraft.copilotquota.legacy.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        store = SharedSnapshotStore(defaults: defaults)
        vault = InMemoryCredentialVault()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        super.tearDown()
    }

    func testLegacyV1MigrationImportsCopilotAccountSettingsAndSnapshotIdempotently() throws {
        let legacyKeychain = InMemoryCredentialStore(
            initial: StoredCredentials(
                accessToken: "ghu_v1_token",
                refreshToken: "ghr_v1_refresh",
                expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )
        legacyDefaults.set(10, forKey: "refreshIntervalMinutes")
        legacyDefaults.set(true, forKey: "showDockIcon")
        let oldDisplay = QuotaDisplay(
            percentRemaining: 64,
            primaryCategoryLabel: "Premium requests",
            planLabel: "Copilot Pro",
            login: "octocat",
            resetDate: "2026-12-01",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            premium: CategoryQuota(percentRemaining: 64, unlimited: false, entitlement: 300, remaining: 192),
            primaryEntitlement: 300,
            primaryRemaining: 192,
            primaryUnlimited: false
        )
        legacyDefaults.set(try JSONEncoder().encode(oldDisplay), forKey: "cachedDisplay")

        let firstRun = LegacyV1Migration.migrateIfNeeded(
            store: store,
            vault: vault,
            legacyDefaults: legacyDefaults,
            legacyCredentialStore: legacyKeychain
        )
        XCTAssertTrue(firstRun)
        XCTAssertEqual(store.refreshIntervalMinutes, 10)
        XCTAssertTrue(store.showDockIcon)
        XCTAssertEqual(store.accounts.count, 1)

        let migrated = try XCTUnwrap(store.accounts.first)
        XCTAssertEqual(migrated.kind, .copilot)
        guard case .oauth(let creds) = vault.load(accountID: migrated.id) else {
            return XCTFail("Expected migrated OAuth credentials in new vault")
        }
        XCTAssertEqual(creds.accessToken, "ghu_v1_token")
        XCTAssertEqual(creds.refreshToken, "ghr_v1_refresh")

        let migratedSnap = try XCTUnwrap(store.snapshot(for: migrated.id))
        XCTAssertEqual(migratedSnap.accountLabel, "octocat")
        if case .metered(let pct, let rem, let ent, _, _) = migratedSnap.metric {
            XCTAssertEqual(pct, 64)
            XCTAssertEqual(rem, 192)
            XCTAssertEqual(ent, 300)
        } else {
            XCTFail("Expected metered metric")
        }

        // Second run is a no-op (idempotent).
        let secondRun = LegacyV1Migration.migrateIfNeeded(
            store: store,
            vault: vault,
            legacyDefaults: legacyDefaults,
            legacyCredentialStore: legacyKeychain
        )
        XCTAssertFalse(secondRun)
        XCTAssertEqual(store.accounts.count, 1)
    }

    @MainActor
    func testCoordinatorRefreshAllIsolatesProviderFailures() async {
        let deepseekAcc = ProviderAccount(kind: .deepseek, sortOrder: 0)
        let glmAcc = ProviderAccount(kind: .glm, region: GLMRegion.cn.rawValue, sortOrder: 1)
        store.accounts = [deepseekAcc, glmAcc]

        let registry = ProviderRegistry(providers: [
            StubProvider(kind: .deepseek) { account in
                ProviderSnapshot(
                    accountID: account.id,
                    kind: .deepseek,
                    metric: .balance(amount: 55.0, currency: "CNY", granted: nil, toppedUp: 55.0)
                )
            },
            StubProvider(kind: .glm) { _ in
                throw ProviderError.unauthorized
            },
        ])

        var reloadCount = 0
        let coordinator = QuotaCoordinator(
            store: store,
            vault: vault,
            registry: registry,
            autoStart: false,
            reloadWidgets: { reloadCount += 1 }
        )

        await coordinator.refreshAll()

        XCTAssertNotNil(coordinator.snapshots[deepseekAcc.id])
        XCTAssertNil(coordinator.accountErrors[deepseekAcc.id])
        XCTAssertNil(coordinator.snapshots[glmAcc.id])
        XCTAssertNotNil(coordinator.accountErrors[glmAcc.id])
        XCTAssertEqual(reloadCount, 1)
    }
}
