import XCTest

final class ProvidersDecodingTests: XCTestCase {
    func testDeepSeekBalanceDecodingAndMapping() throws {
        let json = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "USD",
              "total_balance": "0.00",
              "granted_balance": "0.00",
              "topped_up_balance": "0.00"
            },
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: json)
        let acc = ProviderAccount(kind: .deepseek)
        let snap = try DeepSeekProvider.map(response: decoded, account: acc)

        guard case .balance(let amount, let currency, let granted, let toppedUp) = snap.metric else {
            return XCTFail("Expected balance metric")
        }
        XCTAssertEqual(amount, 110.0)
        XCTAssertEqual(currency, "CNY")
        XCTAssertEqual(granted, 10.0)
        XCTAssertEqual(toppedUp, 100.0)
    }

    func testOpenRouterCreditsDecodingAndMapping() throws {
        let json = """
        {
          "data": {
            "total_credits": 25.0,
            "total_usage": 7.55
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: json)
        let acc = ProviderAccount(kind: .openrouter)
        let snap = OpenRouterProvider.map(response: decoded, account: acc)

        guard case .balance(let amount, let currency, _, let toppedUp) = snap.metric else {
            return XCTFail("Expected balance metric")
        }
        XCTAssertEqual(amount, 17.45, accuracy: 0.001)
        XCTAssertEqual(currency, "USD")
        XCTAssertEqual(toppedUp, 25.0)
    }

    func testGLMQuotaDualWindowDecodingAndMapping() throws {
        let json = """
        {
          "success": true,
          "code": 200,
          "msg": "success",
          "data": {
            "level": "pro",
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 30.0,
                "nextResetTime": 1780000000000
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "number": 1,
                "percentage": 55.0,
                "nextResetTime": 1780500000000
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GLMQuotaResponse.self, from: json)
        let acc = ProviderAccount(kind: .glm, region: GLMRegion.cn.rawValue)
        let snap = try GLMProvider.map(response: decoded, account: acc)

        XCTAssertEqual(snap.planLabel, "GLM Coding Pro")
        guard case .rollingWindows(let windows) = snap.metric else {
            return XCTFail("Expected rollingWindows metric")
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].label, "5h")
        XCTAssertEqual(windows[0].percentRemaining, 70.0)
        XCTAssertEqual(windows[1].label, "7d")
        XCTAssertEqual(windows[1].percentRemaining, 45.0)
        XCTAssertEqual(windows[0].resetAt?.timeIntervalSince1970 ?? 0, 1_780_000_000, accuracy: 1.0)
    }
}
