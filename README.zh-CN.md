# Copilot Quota

**[English](README.md)** | 简体中文

仿系统电池样式的 macOS 桌面小组件（WidgetKit）：一个圆环 + Copilot 图标 + 剩余百分比。

| 桌面小组件 | App |
| :---: | :---: |
| ![小组件](preview/widget.png) | ![App](preview/app.png) |

## 安装

下载并解压 [最新版本](https://github.com/addozhang/CopilotQuota/releases/latest)，
把 `Copilot Quota.app` 拖入「应用程序」，然后放行一次 Gatekeeper：

```bash
xattr -dr com.apple.quarantine "/Applications/Copilot Quota.app"
```

（或者：系统设置 → 隐私与安全性 → **仍要打开**。）
需要 macOS 14+ · Universal 双架构（Apple Silicon 和 Intel）。

## 使用

1. 打开 **Copilot Quota** → 用 GitHub 登录（OAuth 设备授权流程）。
2. 右键桌面 → 编辑小组件 → 添加 **Copilot**。

点击小组件会打开 App，里面可以选刷新间隔（5 / 10 / 30 / 60 分钟）。

## 从源码构建

用 Xcode 打开 `CopilotQuota.xcodeproj`，`⌘R` 运行；或：

```bash
xcodebuild -project CopilotQuota.xcodeproj -target CopilotQuota -configuration Release build SYMROOT=build
```

## 说明

- 配额来自 `api.github.com/copilot_internal/user`（premium → chat → completions），
  用设备流程拿到的 token 拉取。
- token（scope 仅 `read:user`）不出本机。widget 刷新受系统每日预算限制，
  所选间隔只是下限。
- widget 扩展已沙盒化，通过偏好域读写例外共享数据与 token，App 未运行时
  widget 可自行轮换约 8 小时寿命的 OAuth token——个人使用 / Developer ID
  分发没问题；上架 Mac App Store 需改为 App Group 方案（商店拒绝临时例外权限）。
- 退出登录 / 手动刷新在 App 里。界面支持英文和简体中文，跟随系统语言。
- Copilot 图标基于 GitHub [Octicons](https://github.com/primer/octicons)（MIT）。
