# QuotaRing

**[English](README.md)** | 简体中文

**[官网](https://solocraft.app/copilot-quota) · [下载 DMG](https://github.com/addozhang/QuotaRing/releases/latest)**

> 原 **Copilot Quota** —— 在 v2.0 升级为多 AI 配额与余额监控工具，延续极简的 macOS 系统电池小组件美学。

仿系统电池样式的 macOS 菜单栏应用与桌面小组件（WidgetKit），一站式查看你的 AI 订阅配额与预付余额：

| 桌面小组件 | 菜单栏 Popover |
| :---: | :---: |
| <img src="preview/widget.png" width="380" alt="桌面小组件" /> | <img src="preview/app.png" width="340" alt="菜单栏 Popover" /> |

- **GitHub Copilot** — OAuth 设备授权 · 月度高级请求配额与重置倒计时
- **DeepSeek** — API Key · 预付余额（`CNY` / `USD`，含充值/赠金明细，支持可选参考上限与低余额变色）
- **OpenRouter** — API Key · 美元预付额度与可选预算上限
- **GLM Coding Plan** — API Key · 同时支持国内站（`open.bigmodel.cn`）与国际站（`api.z.ai`）· 5 小时与周滚动窗口
- *（v2.1 规划：Google AI Pro 支持与低配额系统通知）*

## 安装

### 下载 DMG

下载 [最新版本](https://github.com/addozhang/QuotaRing/releases/latest) 的 DMG，
打开并把 `QuotaRing.app` 拖入「应用程序」——App 使用 **Developer ID 证书签名并通过 Apple 公证**。

### Homebrew

```bash
brew tap addozhang/quotaring https://github.com/addozhang/QuotaRing
brew install --cask quotaring
```

需要 macOS 14+ · Universal 双架构（Apple Silicon 和 Intel）。

## 使用

1. 点击顶部菜单栏中的 **QuotaRing** 图标（默认仅显示图标，隐藏 Dock 图标）。
2. 点击 **+** 连接 GitHub Copilot、DeepSeek、GLM Coding 或 OpenRouter。
   *（从 Copilot Quota v1.x 升级时，原有的 GitHub Copilot Keychain 凭证与偏好设置会自动无缝迁移。）*
3. 右键桌面 → **编辑小组件** → 搜索 **QuotaRing**：
   - **小号小组件**：单个电池风圆环（右键「编辑小组件」可自由选择绑定的服务）。
   - **中号小组件**：仿系统电池中号小组件，一排并列展示 2–4 个圆环。

## 从源码构建与测试

```bash
# 构建 Universal Release
./scripts/build-app.sh

# 运行单元测试
xcodebuild -project CopilotQuota.xcodeproj -scheme CopilotQuota -configuration Debug test
```

## 架构与安全说明

- **仅宿主持有凭证**：所有 OAuth Token 与 API Key 按账号隔离存储在 **macOS Keychain**（`app.solocraft.quotaring`），永不离开本机。
- **纯渲染器小组件**：所有服务的并发刷新与 Token 轮换均由常驻菜单栏的宿主 App 统一完成；沙盒化的 Widget 扩展**零网络权限、零 Keychain 访问**，仅读取脱敏后的展示快照。
- 界面支持英文与简体中文，跟随系统语言。
- Copilot 图标基于 GitHub [Octicons](https://github.com/primer/octicons)（MIT）。
