import XCTest

final class QuotaCoreModelsTests: XCTestCase {
    func testMeteredRingPresentationTonesAndCounts() {
        let acc = ProviderAccount(kind: .copilot)

        let normal = ProviderSnapshot(
            accountID: acc.id,
            kind: .copilot,
            metric: .metered(percentRemaining: 83, remaining: 249, entitlement: 300, resetAt: nil, unlimited: false)
        )
        let p1 = RingPresentation.from(snapshot: normal, account: acc)
        XCTAssertEqual(p1.fillFraction, 0.83)
        XCTAssertEqual(p1.tone, .normal)
        XCTAssertEqual(p1.primaryText, "83%")
        XCTAssertEqual(p1.secondaryText, "249 / 300")

        let warning = ProviderSnapshot(
            accountID: acc.id,
            kind: .copilot,
            metric: .metered(percentRemaining: 15, remaining: 45, entitlement: 300, resetAt: nil, unlimited: false)
        )
        XCTAssertEqual(RingPresentation.from(snapshot: warning, account: acc).tone, .warning)

        let critical = ProviderSnapshot(
            accountID: acc.id,
            kind: .copilot,
            metric: .metered(percentRemaining: 5, remaining: 15, entitlement: 300, resetAt: nil, unlimited: false)
        )
        XCTAssertEqual(RingPresentation.from(snapshot: critical, account: acc).tone, .critical)

        let unlimited = ProviderSnapshot(
            accountID: acc.id,
            kind: .copilot,
            metric: .metered(percentRemaining: 100, remaining: nil, entitlement: nil, resetAt: nil, unlimited: true)
        )
        let p4 = RingPresentation.from(snapshot: unlimited, account: acc)
        XCTAssertEqual(p4.primaryText, "∞")
        XCTAssertEqual(p4.fillFraction, 1.0)
        XCTAssertEqual(p4.tone, .normal)
    }

    func testRollingWindowsUsesTightestWindowForRing() {
        let acc = ProviderAccount(kind: .glm, region: GLMRegion.cn.rawValue)
        let snap = ProviderSnapshot(
            accountID: acc.id,
            kind: .glm,
            metric: .rollingWindows([
                QuotaWindow(id: "5h", label: "5h", percentRemaining: 72),
                QuotaWindow(id: "7d", label: "7d", percentRemaining: 18),
            ])
        )
        let pres = RingPresentation.from(snapshot: snap, account: acc)
        XCTAssertEqual(pres.fillFraction, 0.18)
        XCTAssertEqual(pres.tone, .warning)
        XCTAssertEqual(pres.primaryText, "18%")
        XCTAssertEqual(pres.secondaryText, "5h 72% · 7d 18%")
    }

    func testBalancePresentationWithAndWithoutCap() {
        // Without cap: full ring, threshold-based coloring.
        let noCapAcc = ProviderAccount(kind: .deepseek, warningThreshold: 10, criticalThreshold: 5)
        let healthy = ProviderSnapshot(
            accountID: noCapAcc.id,
            kind: .deepseek,
            metric: .balance(amount: 42.5, currency: "CNY", granted: 10, toppedUp: 32.5)
        )
        let pHealthy = RingPresentation.from(snapshot: healthy, account: noCapAcc)
        XCTAssertEqual(pHealthy.fillFraction, 1.0)
        XCTAssertEqual(pHealthy.tone, .normal)
        XCTAssertEqual(pHealthy.primaryText, "¥42.5")
        XCTAssertEqual(pHealthy.secondaryText, "¥32.50 +¥10")

        let low = ProviderSnapshot(
            accountID: noCapAcc.id,
            kind: .deepseek,
            metric: .balance(amount: 8.0, currency: "CNY", granted: nil, toppedUp: 8.0)
        )
        XCTAssertEqual(RingPresentation.from(snapshot: low, account: noCapAcc).tone, .warning)

        let crit = ProviderSnapshot(
            accountID: noCapAcc.id,
            kind: .deepseek,
            metric: .balance(amount: 3.2, currency: "CNY", granted: nil, toppedUp: 3.2)
        )
        XCTAssertEqual(RingPresentation.from(snapshot: crit, account: noCapAcc).tone, .critical)

        // With reference cap: proportional ring.
        let capAcc = ProviderAccount(kind: .openrouter, balanceReferenceCap: 20, warningThreshold: 2, criticalThreshold: 1)
        let orSnap = ProviderSnapshot(
            accountID: capAcc.id,
            kind: .openrouter,
            metric: .balance(amount: 10.0, currency: "USD", granted: nil, toppedUp: 20.0)
        )
        let pCap = RingPresentation.from(snapshot: orSnap, account: capAcc)
        XCTAssertEqual(pCap.fillFraction, 0.5)
        XCTAssertEqual(pCap.tone, .normal)
        XCTAssertEqual(pCap.primaryText, "$10.0")
    }

    func testWidgetSlotResolverSingleAndDualSelection() {
        let copilot = ProviderAccount(kind: .copilot, sortOrder: 0)
        let glm = ProviderAccount(kind: .glm, region: GLMRegion.cn.rawValue, sortOrder: 1)
        let deepseek = ProviderAccount(kind: .deepseek, sortOrder: 2)

        let copilotSnap = ProviderSnapshot(
            accountID: copilot.id,
            kind: .copilot,
            metric: .metered(percentRemaining: 83, remaining: 249, entitlement: 300, resetAt: nil, unlimited: false)
        )
        let glmSnap = ProviderSnapshot(
            accountID: glm.id,
            kind: .glm,
            metric: .rollingWindows([
                QuotaWindow(id: "5h", label: "5h", percentRemaining: 70),
                QuotaWindow(id: "7d", label: "7d", percentRemaining: 45),
            ])
        )
        let deepseekSnap = ProviderSnapshot(
            accountID: deepseek.id,
            kind: .deepseek,
            metric: .balance(amount: 42.5, currency: "CNY", granted: nil, toppedUp: 42.5)
        )

        let accounts = [copilot, glm, deepseek]
        let snapshots = [copilot.id: copilotSnap, glm.id: glmSnap, deepseek.id: deepseekSnap]

        // Single ring respects explicit selection.
        let single = WidgetSlotResolver.resolveSingle(
            selectedAccountID: deepseek.id,
            accounts: accounts,
            snapshots: snapshots
        )
        XCTAssertEqual(single?.kind, .deepseek)
        XCTAssertEqual(single?.presentation.primaryText, "¥42.5")

        // Dual ring with no selection defaults to the multi-window provider (GLM 5h + 7d).
        let defaultDual = WidgetSlotResolver.resolveDual(
            selectedAccountID: nil,
            accounts: accounts,
            snapshots: snapshots
        )
        XCTAssertEqual(defaultDual.count, 2)
        XCTAssertEqual(defaultDual[0].title, "GLM Coding")
        XCTAssertEqual(defaultDual[0].windowLabel, "5h")
        XCTAssertEqual(defaultDual[0].presentation.primaryText, "70%")
        XCTAssertEqual(defaultDual[1].title, "GLM Coding")
        XCTAssertEqual(defaultDual[1].windowLabel, "7d")
        XCTAssertEqual(defaultDual[1].presentation.primaryText, "45%")

        // Dual ring with GLM selected splits into GLM 5h + GLM 7d (never mixes in Copilot).
        let glmDual = WidgetSlotResolver.resolveDual(
            selectedAccountID: glm.id,
            accounts: accounts,
            snapshots: snapshots
        )
        XCTAssertEqual(glmDual.count, 2)
        XCTAssertEqual(glmDual[0].kind, .glm)
        XCTAssertEqual(glmDual[1].kind, .glm)

        // Dual ring with a single-metric provider only shows that provider (never mixes another).
        let copilotDual = WidgetSlotResolver.resolveDual(
            selectedAccountID: copilot.id,
            accounts: accounts,
            snapshots: snapshots
        )
        XCTAssertEqual(copilotDual.count, 1)
        XCTAssertEqual(copilotDual[0].kind, .copilot)
    }
}
