# Winenv

[English](./README.md)

[![CI](https://github.com/YangYuS8/winenv/actions/workflows/ci.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/ci.yml)
[![Release](https://github.com/YangYuS8/winenv/actions/workflows/release.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/release.yml)
[![Docs](https://github.com/YangYuS8/winenv/actions/workflows/pages.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/pages.yml)
[![GitHub Release](https://img.shields.io/github/v/release/YangYuS8/winenv)](https://github.com/YangYuS8/winenv/releases/latest)

Winenv 是面向 Windows 11 的软件与开发环境管理层。它不建立第四套软件仓库，而是把 WinGet、Scoop 和 mise 组织成一套短命令、实时搜索、可组合 Profile 和可复现安装流程。

完整指南、命令参考和自动同步的更新日志请访问 **[Winenv 中文文档](https://yangyus8.top/winenv/zh/)**。

## 安装

在普通 PowerShell 中执行：

```powershell
irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1 | iex
```

安装器会从最新稳定版 [GitHub Release](https://github.com/YangYuS8/winenv/releases/latest) 下载文件、校验 SHA-256、创建全局 `win` 命令，并复用电脑上已经兼容的前置软件。

从这些命令开始：

```powershell
win                 # 打开交互式软件选择器
win vscode          # 搜索并安装软件
win scan            # 只读扫描现有 Windows 软件
win check           # 检查环境和冲突
win help            # 查看简明帮助
```

英文是项目的主语言。Winenv 会自动跟随中文 Windows 界面，也可以随时用 `win lang en`、`win lang zh` 或 `win lang auto` 切换。

详细选项见[开始使用](https://yangyus8.top/winenv/zh/guide/getting-started)。

## 设计原则

- WinGet 管理需要 Windows 集成的应用，Scoop 管理便携 CLI，mise 管理需要多版本切换的开发工具。
- 搜索实时查询各管理器，不维护容易过期的软件索引，也不替用户静默猜测来源。
- 内置 Profile 只包含 Winenv 运行所需能力；个人和社区 Profile 独立存放、自由组合。
- 已经安装大量软件的电脑也能扫描并选择性纳入，不要求重装系统。
- 版本、更新日志、带校验的 Release 资产和文档站均由 GitHub Actions 自动生成。

## 参与贡献

欢迎贡献。请先阅读[贡献指南](./CONTRIBUTING.zh-CN.md)，同时遵守[行为准则](./CODE_OF_CONDUCT.zh-CN.md)、[安全政策](./SECURITY.zh-CN.md)与[治理规则](./GOVERNANCE.zh-CN.md)。英文是权威版本；用户可见的修改应在同一 Pull Request 中同步简体中文。

## 本地维护文档

```powershell
npm ci
npm run docs:dev
```

文档位于 `docs/`。根目录 `CHANGELOG.md` 是发布历史的唯一来源；站点副本会在构建时生成，不要手工修改。

## 许可证

[MIT](./LICENSE)
