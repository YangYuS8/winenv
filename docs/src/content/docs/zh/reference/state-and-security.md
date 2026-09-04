---
title: "状态、存储与安全"
description: "Winenv 文档：状态、存储与安全。"
sidebar:
  order: 3
---

<span id="状态、存储与安全"></span>

Winenv 把声明状态放在自己的目录中，不保存软件账号、密码或登录令牌。

## 本机文件

```text
%LOCALAPPDATA%\Winenv\state.json
%LOCALAPPDATA%\Winenv\config.json
%LOCALAPPDATA%\Winenv\profiles\*.json
%LOCALAPPDATA%\Winenv\logs\*.log
%USERPROFILE%\.config\mise\conf.d\winenv.toml
```

| 路径 | 内容 |
| --- | --- |
| `state.json` | 已经执行的一次性 migration |
| `config.json` | 界面语言、Profile 注册表与这台机器做出的冲突选择 |
| `profiles/*.json` | 本地、远程和自动生成 Profile 的稳定快照 |
| `logs/*.log` | MSI 详细安装日志 |
| `winenv.toml` | 从当前有效声明生成的 mise 独立配置片段 |

旧版单一 `user-profile.json` 会在首次运行时迁移为独立快照，原文件保留不删。

## 谁拥有软件

Profile 只声明需求；包的实际所有者仍是：

- WinGet：安装器和 Windows 集成应用；
- Scoop：bucket 或独立 manifest 安装的软件；
- mise：版本化开发工具；
- 发布者：无法纳入目录的手工安装软件。

因此停用 Profile 不卸载软件，更新和删除也继续尊重各管理器自己的 pin、hold、版本配置和安全规则。

## 网络来源

- 安装 Winenv 时，从 GitHub Release 下载版本资产并校验仓库发布的 SHA-256；
- 远程 Profile 和 Scoop manifest 只接受 HTTPS，刷新必须再次显式执行 `win use`；
- 第三方 Scoop bucket 会显示完整 Git URL，并要求单独确认；
- Winenv 不直接从 URL 运行裸 EXE/MSI，必须先保存到本地检查实际文件。

HTTPS 和哈希能确认传输与文件内容，不等于替发布者背书。使用社区 Profile、bucket 或安装器前，仍应判断维护者是否可信。

## 权限边界

Winenv 不会为了完成安装而静默：

- 提权到管理员；
- 修改 PowerShell 执行策略；
- 启用 WinGet 本地 manifest 安全设置；
- 更换同名第三方 bucket 的来源；
- 接受损坏或无法验证的安装器签名。

需要系统权限时，Windows 或上游安装器会按自己的方式明确请求。

## 当前不做的事情

- 删除 Windows 内置组件；
- 修改 Defender、BitLocker 或 Windows Update 策略；
- 自动安装驱动；
- 猜测任意 EXE 的静默、升级或卸载参数；
- 保存登录令牌和软件私有数据；
- 绕过管理器自身的保留、pin、hold 或清理策略。
