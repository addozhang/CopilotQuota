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

    func testKimiUsageDualWindowDecodingAndMapping() throws {
        let json = """
        {
          "user": {
            "membership": {
              "level": "LEVEL_ADVANCED"
            }
          },
          "usage": {
            "limit": "100",
            "used": "2",
            "remaining": "98",
            "resetTime": "2026-08-20T07:05:56Z"
          },
          "limits": [
            {
              "window": {
                "duration": 300,
                "timeUnit": "TIME_UNIT_MINUTE"
              },
              "detail": {
                "limit": "100",
                "used": "7",
                "remaining": "93",
                "resetTime": "2026-08-14T07:05:56Z"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(KimiUsageResponse.self, from: json)
        let acc = ProviderAccount(kind: .kimi)
        let snap = try KimiProvider.map(response: decoded, account: acc)

        XCTAssertEqual(snap.kind, .kimi)
        XCTAssertEqual(snap.planLabel, "Advanced")
        guard case .rollingWindows(let windows) = snap.metric else {
            return XCTFail("Expected rollingWindows metric")
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].label, "5h")
        XCTAssertEqual(windows[0].percentRemaining, 93.0, accuracy: 0.01)
        XCTAssertNotNil(windows[0].resetAt)
        XCTAssertEqual(windows[1].label, "7d")
        XCTAssertEqual(windows[1].percentRemaining, 98.0, accuracy: 0.01)
        XCTAssertNotNil(windows[1].resetAt)
    }

    func testKimiUsageNumericValuesFallbackToUsed() throws {
        let json = """
        {
          "usage": {
            "limit": 200,
            "used": 50
          },
          "limits": [
            {
              "window": {
                "duration": 5,
                "timeUnit": "TIME_UNIT_HOUR"
              },
              "detail": {
                "limit": 100,
                "used": 40
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(KimiUsageResponse.self, from: json)
        let acc = ProviderAccount(kind: .kimi)
        let snap = try KimiProvider.map(response: decoded, account: acc)

        XCTAssertNil(snap.planLabel)
        guard case .rollingWindows(let windows) = snap.metric else {
            return XCTFail("Expected rollingWindows metric")
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].label, "5h")
        XCTAssertEqual(windows[0].percentRemaining, 60.0, accuracy: 0.01)
        XCTAssertEqual(windows[1].label, "7d")
        XCTAssertEqual(windows[1].percentRemaining, 75.0, accuracy: 0.01)
    }

    func testMiniMaxRemainsDualWindowDecodingAndMapping() throws {
        let json = """
        {
          "model_remains": [
            {
              "model_name": "MiniMax-M2.7",
              "current_interval_total_count": 1500,
              "current_interval_usage_count": 1200,
              "current_interval_remaining_percent": 100,
              "start_time": 1773896400000,
              "end_time": 1773914400000,
              "remains_time": 7196264,
              "current_weekly_total_count": 50000,
              "current_weekly_usage_count": 35000,
              "current_weekly_remaining_percent": 100,
              "weekly_start_time": 1773619200000,
              "weekly_end_time": 1774224000000,
              "weekly_remains_time": 316796264
            }
          ],
          "base_resp": {
            "status_code": 0,
            "status_msg": ""
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MiniMaxRemainsResponse.self, from: json)
        let acc = ProviderAccount(kind: .minimax, region: MiniMaxRegion.cn.rawValue)
        let snap = try MiniMaxProvider.map(response: decoded, account: acc)

        XCTAssertEqual(snap.kind, .minimax)
        XCTAssertEqual(snap.planLabel, "MiniMax-M2.7")
        guard case .rollingWindows(let windows) = snap.metric else {
            return XCTFail("Expected rollingWindows metric")
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].label, "5h")
        XCTAssertEqual(windows[0].percentRemaining, 80.0, accuracy: 0.01)
        XCTAssertEqual(windows[0].resetAt?.timeIntervalSince1970 ?? 0, 1_773_914_400, accuracy: 1.0)
        XCTAssertEqual(windows[1].label, "7d")
        XCTAssertEqual(windows[1].percentRemaining, 70.0, accuracy: 0.01)
        XCTAssertEqual(windows[1].resetAt?.timeIntervalSince1970 ?? 0, 1_774_224_000, accuracy: 1.0)
    }

    func testMiniMaxRemainsErrorStatusCodes() throws {
        let authJson = """
        {
          "base_resp": {
            "status_code": 1004,
            "status_msg": "cookie is missing"
          }
        }
        """.data(using: .utf8)!

        let authDecoded = try JSONDecoder().decode(MiniMaxRemainsResponse.self, from: authJson)
        let acc = ProviderAccount(kind: .minimax, region: MiniMaxRegion.global.rawValue)
        XCTAssertThrowsError(try MiniMaxProvider.map(response: authDecoded, account: acc)) { error in
            XCTAssertEqual(error as? ProviderError, .unauthorized)
        }
    }
}
