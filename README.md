# Winenv

[![CI](https://github.com/YangYuS8/winenv/actions/workflows/ci.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/ci.yml)
[![Release](https://github.com/YangYuS8/winenv/actions/workflows/release.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/release.yml)
[![Docs](https://github.com/YangYuS8/winenv/actions/workflows/pages.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/pages.yml)
[![GitHub Release](https://img.shields.io/github/v/release/YangYuS8/winenv)](https://github.com/YangYuS8/winenv/releases/latest)

Winenv 是面向 Windows 11 的软件与开发环境管理层。它不建立第四套软件仓库，而是把 WinGet、Scoop 和 mise 组织成一套短命令、实时搜索、可组合 Profile 和可复现的安装流程。

完整说明、命令参考与自动同步的更新日志请访问：

**[Winenv 文档站](https://yangyus8.top/winenv/)**

## 安装

在普通 PowerShell 中执行：

```powershell
irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1 | iex
```

安装器会从 [GitHub Releases](https://github.com/YangYuS8/winenv/releases/latest) 获取最新稳定版、校验 SHA-256、创建全局 `win` 命令，并复用机器上已经兼容的前置软件。

安装后从这几个命令开始：

```powershell
win                 # 打开交互式软件选择器
win vscode          # 搜索并安装软件
win scan            # 只读扫描现有 Windows 软件
win check           # 检查环境和冲突
win help            # 查看简明帮助
```

详细安装选项见[开始使用](https://yangyus8.top/winenv/guide/getting-started)。

## 设计原则

- WinGet 管理需要 Windows 集成的应用，Scoop 管理便携 CLI，mise 管理需要多版本切换的开发工具。
- 搜索实时查询各管理器，不维护容易过期的软件索引，也不替用户静默猜测来源。
- 内置 Profile 只包含 Winenv 运行所需能力；个人和社区 Profile 独立存放、自由组合。
- 已经安装了大量软件的电脑可以直接扫描并选择性纳入，不要求重装系统。
- 版本、更新日志、Release 资产和文档站均由 GitHub Actions 自动生成。

## 本地维护文档

```powershell
npm ci
npm run docs:dev
```

文档位于 `docs/`。根目录 `CHANGELOG.md` 是更新日志的唯一来源，构建时会自动生成站点页面，不要手工编辑 `docs/changelog.md`。

## License

[MIT](./LICENSE)
