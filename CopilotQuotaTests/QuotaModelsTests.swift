import XCTest

final class QuotaModelsTests: XCTestCase {
    func testDecodesPremiumQuotaWithEntitlementAndRemaining() throws {
        let json = """
        {
          "login": "octocat",
          "copilot_plan": "individual",
          "quota_reset_date_utc": "2026-12-01T00:00:00.000Z",
          "quota_snapshots": {
            "premium_interactions": {
              "entitlement": 300,
              "remaining": 249,
              "percent_remaining": 83.0,
              "unlimited": false
            },
            "chat": {
              "unlimited": true
            },
            "completions": {
              "unlimited": true
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUserResponse.self, from: json)
        XCTAssertEqual(response.login, "octocat")
        XCTAssertEqual(response.friendlyPlan, "Copilot Pro")

        let display = try XCTUnwrap(response.display)
        XCTAssertEqual(display.percentRemaining, 83.0)
        XCTAssertEqual(display.primaryCategoryLabel, "Premium requests")
        XCTAssertEqual(display.primaryCountText, "249 / 300")
        XCTAssertFalse(display.isPrimaryUnlimited)
    }

    func testFallsBackToMeteredChatWhenPremiumIsUnlimited() throws {
        let json = """
        {
          "login": "freeuser",
          "copilot_plan": "free",
          "quota_reset_date": "2026-12-01",
          "quota_snapshots": {
            "premium_interactions": { "unlimited": true },
            "chat": { "entitlement": 50, "remaining": 20, "percent_remaining": 40.0, "unlimited": false }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUserResponse.self, from: json)
        XCTAssertEqual(response.friendlyPlan, "Copilot Free")
        let display = try XCTUnwrap(response.display)
        XCTAssertEqual(display.primaryCategoryLabel, "Chat")
        XCTAssertEqual(display.percentRemaining, 40.0)
        XCTAssertEqual(display.primaryCountText, "20 / 50")
    }

    func testAllUnlimitedPlanShowsUnlimitedAndNoCountText() throws {
        let json = """
        {
          "copilot_plan": "enterprise",
          "quota_snapshots": {
            "premium_interactions": { "unlimited": true }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CopilotUserResponse.self, from: json)
        XCTAssertEqual(response.friendlyPlan, "Copilot Enterprise")
        let display = try XCTUnwrap(response.display)
        XCTAssertTrue(display.isPrimaryUnlimited)
        XCTAssertEqual(display.percentRemaining, 100)
        XCTAssertNil(display.primaryCountText)
    }

    func testParseResetDateFormatsAndDaysUntilReset() throws {
        let dayOnly = try XCTUnwrap(QuotaDisplay.parseResetDate("2026-12-01"))
        let iso = try XCTUnwrap(QuotaDisplay.parseResetDate("2026-12-01T00:00:00Z"))
        let isoFractional = try XCTUnwrap(QuotaDisplay.parseResetDate("2026-12-01T00:00:00.000Z"))
        XCTAssertEqual(dayOnly, iso)
        XCTAssertEqual(iso, isoFractional)
        XCTAssertNil(QuotaDisplay.parseResetDate("not-a-date"))
        XCTAssertNil(QuotaDisplay.parseResetDate(nil))

        let display = QuotaDisplay(
            percentRemaining: 50,
            primaryCategoryLabel: "Premium requests",
            planLabel: "Copilot Pro",
            login: "octocat",
            resetDate: "2026-12-01T00:00:00Z",
            fetchedAt: .now,
            premium: nil
        )
        let ref = try XCTUnwrap(QuotaDisplay.parseResetDate("2026-11-21T12:00:00Z"))
        XCTAssertEqual(display.daysUntilReset(from: ref), 10)

        let past = try XCTUnwrap(QuotaDisplay.parseResetDate("2026-12-05T00:00:00Z"))
        XCTAssertEqual(display.daysUntilReset(from: past), 0)
    }

    func testQuotaDisplayBackwardCompatibleDecode() throws {
        // Older v1.3.0 cachedDisplay JSON without primaryEntitlement/primaryRemaining/primaryUnlimited.
        let legacyJSON = """
        {
          "percentRemaining": 75,
          "primaryCategoryLabel": "Premium requests",
          "planLabel": "Copilot Pro",
          "login": "octocat",
          "fetchedAt": 0,
          "premium": { "percentRemaining": 75, "unlimited": false }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(QuotaDisplay.self, from: legacyJSON)
        XCTAssertEqual(decoded.percentRemaining, 75)
        XCTAssertFalse(decoded.isPrimaryUnlimited)
        XCTAssertNil(decoded.primaryCountText)
    }
}
