# QuotaRing

English | **[简体中文](README.zh-CN.md)**

**[Website](https://solocraft.app/copilot-quota) · [Download DMG](https://github.com/addozhang/QuotaRing/releases/latest)**

> Formerly **Copilot Quota** — evolved in v2.0 into a multi-AI quota monitor while keeping the same minimalist macOS battery-widget aesthetic.

Battery-style macOS menu bar app and desktop widgets (WidgetKit) for your AI subscriptions and API balances:

| Desktop widgets | Menu bar popover |
| :---: | :---: |
| <img src="preview/widget.png" width="380" alt="Desktop widgets" /> | <img src="preview/app.png" width="340" alt="Menu bar popover" /> |

- **GitHub Copilot** — OAuth Device Flow · monthly premium request quota & reset countdown
- **DeepSeek** — API Key · prepaid balance (`CNY` / `USD`, top-up + grant breakdown, optional budget cap)
- **OpenRouter** — API Key · prepaid USD credits with optional budget cap
- **GLM Coding Plan** — API Key · BigModel (`open.bigmodel.cn`) & Z.ai (`api.z.ai`) · 5-hour & weekly rolling windows
- *(Planned for v2.1: Google AI Pro & low-quota system notifications)*

## Install

### Download DMG

Download [the latest release](https://github.com/addozhang/QuotaRing/releases/latest)
(DMG), open it and drag `QuotaRing.app` into **/Applications** — signed with a
**Developer ID certificate and notarized by Apple**.

### Homebrew

```bash
brew tap addozhang/quotaring https://github.com/addozhang/QuotaRing
brew install --cask quotaring
```

Requires macOS 14+ · universal (Apple Silicon & Intel).

## Usage

1. Open **QuotaRing** from the menu bar (icon-only by default, Dock icon hidden).
2. Click **+** to connect GitHub Copilot, DeepSeek, GLM Coding, or OpenRouter.
   *(Upgrading from Copilot Quota v1.x? Your existing GitHub Copilot Keychain credentials and preferences are migrated automatically.)*
3. Right-click the desktop → **Edit Widgets** → search **QuotaRing**:
   - **Small widget**: single battery-style ring (right-click → Edit Widget to pick any provider).
   - **Medium widget**: macOS Batteries-style row of 2–4 rings side-by-side.

## Build & Test

```bash
# Build Release (universal)
./scripts/build-app.sh

# Run unit tests
xcodebuild -project CopilotQuota.xcodeproj -scheme CopilotQuota -configuration Debug test
```

## Architecture & Security

- **Host-only credentials**: All OAuth tokens and API keys are stored per-account in the **macOS Keychain** (`app.solocraft.quotaring`) and never leave your Mac.
- **Pure-renderer WidgetKit**: The menu bar host app handles all concurrent refreshes and token rotations; the sandboxed widget extension has **zero network access and zero Keychain access**, reading only sanitized display snapshots.
- UI supports English and 简体中文, following the system language.
- The Copilot glyph is based on GitHub [Octicons](https://github.com/primer/octicons) (MIT).
