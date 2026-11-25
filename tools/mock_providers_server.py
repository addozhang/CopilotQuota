#!/usr/bin/env python3
"""
Local mock HTTP server for testing Kimi Code & MiniMax Coding in QuotaRing Debug builds.

Usage:
  1. Start this server:
       python3 tools/mock_providers_server.py
     (Optional: --port 18080 --scenario ok|low|401|1004|fallback)

  2. Launch the Debug build of QuotaRing with env overrides:
       QUOTARING_KIMI_URL="http://127.0.0.1:18080/coding/v1/usages" \
       QUOTARING_MINIMAX_URL="http://127.0.0.1:18080/v1/api/openplatform/coding_plan/remains" \
       QUOTARING_MINIMAX_FALLBACK_URL="http://127.0.0.1:18080/v1/token_plan/remains" \
       build/DerivedData/Build/Products/Debug/QuotaRing.app/Contents/MacOS/QuotaRing

  3. In QuotaRing, click '+' and add Kimi Code (any key e.g. sk-kimi-mock)
     and MiniMax Coding (any key e.g. sk-cp-mock).
"""

import argparse
import datetime
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


def make_kimi_payload(scenario: str) -> tuple[int, dict]:
    if scenario == "401":
        return 401, {"error": {"message": "Invalid API key"}}

    now = datetime.datetime.now(datetime.timezone.utc)
    reset_5h = (now + datetime.timedelta(hours=3, minutes=20)).strftime("%Y-%m-%dT%H:%M:%SZ")
    reset_7d = (now + datetime.timedelta(days=4, hours=6)).strftime("%Y-%m-%dT%H:%M:%SZ")

    if scenario == "low":
        rem_5h, used_5h = "14", "86"
        rem_7d, used_7d = "8", "92"
    else:
        rem_5h, used_5h = "82", "18"
        rem_7d, used_7d = "91", "9"

    return 200, {
        "user": {"membership": {"level": "LEVEL_ADVANCED"}},
        "usage": {
            "limit": "100",
            "used": used_7d,
            "remaining": rem_7d,
            "resetTime": reset_7d,
        },
        "limits": [
            {
                "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
                "detail": {
                    "limit": "100",
                    "used": used_5h,
                    "remaining": rem_5h,
                    "resetTime": reset_5h,
                },
            }
        ],
    }


def make_minimax_payload(scenario: str, is_fallback: bool) -> tuple[int, dict]:
    if scenario == "401":
        return 401, {"base_resp": {"status_code": 1004, "status_msg": "unauthorized"}}
    if scenario == "1004":
        return 200, {"base_resp": {"status_code": 1004, "status_msg": "cookie is missing"}}
    if scenario == "fallback" and not is_fallback:
        return 404, {"base_resp": {"status_code": 404, "status_msg": "not found"}}

    now_ms = int(time.time() * 1000)
    end_5h_ms = now_ms + 2 * 3600 * 1000 + 45 * 60 * 1000
    end_7d_ms = now_ms + 5 * 86400 * 1000

    # MiniMax *_usage_count is actually the REMAINING count.
    if scenario == "low":
        rem_5h, rem_7d = 225, 4200
    else:
        rem_5h, rem_7d = 1140, 38500

    return 200, {
        "base_resp": {"status_code": 0, "status_msg": "success"},
        "model_remains": [
            {
                "model_name": "MiniMax-M2.7",
                "current_interval_total_count": 1500,
                "current_interval_usage_count": rem_5h,
                "start_time": now_ms - 2 * 3600 * 1000,
                "end_time": end_5h_ms,
                "remains_time": end_5h_ms - now_ms,
                "current_weekly_total_count": 50000,
                "current_weekly_usage_count": rem_7d,
                "weekly_start_time": now_ms - 2 * 86400 * 1000,
                "weekly_end_time": end_7d_ms,
                "weekly_remains_time": end_7d_ms - now_ms,
            }
        ],
    }


def main():
    parser = argparse.ArgumentParser(description="QuotaRing local mock server for Kimi & MiniMax")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--scenario", choices=["ok", "low", "401", "1004", "fallback"], default="ok")
    args = parser.parse_args()

    scenario = args.scenario

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            auth = self.headers.get("Authorization", "")
            ua = self.headers.get("User-Agent", "")
            masked = (auth[:18] + "…") if len(auth) > 18 else auth
            print(f"[mock] GET {self.path} | Auth={masked} | UA={ua}", flush=True)

            if self.path.startswith("/coding/v1/usages"):
                status, body = make_kimi_payload(scenario)
            elif self.path.startswith("/v1/api/openplatform/coding_plan/remains"):
                status, body = make_minimax_payload(scenario, is_fallback=False)
            elif self.path.startswith("/v1/token_plan/remains"):
                status, body = make_minimax_payload(scenario, is_fallback=True)
            else:
                status, body = 404, {"error": f"unknown path {self.path}"}

            raw = json.dumps(body).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def log_message(self, format, *a):
            pass

    server = HTTPServer((args.host, args.port), Handler)
    print(f"QuotaRing mock server listening on http://{args.host}:{args.port} (scenario={scenario})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
