---
title: 故障排查
description: 在不削弱 Windows 安全设置的前提下，排查命令、管理器、Profile 冲突和安装器校验问题。
sidebar:
  order: 7
---

先在普通 PowerShell 窗口中执行只读诊断：

```powershell
win ver
win check
```

## 找不到 win 命令

安装后先打开一个新的 PowerShell 窗口，检查命令解析以及当前终端是否加载了自己的配置：

```powershell
Get-Command win -All
$PROFILE
```

通过 `-NoProfile` 启动的终端不会加载安装在 PowerShell 配置中的集成。如果安装中途停止，请先查看原始错误，再考虑重试官方安装命令。不要为了排错清空自己的 PowerShell 配置或重装系统。

## 管理器不可用

`win check` 会区分缺少工具、版本过旧和路径冲突。`win diff` 的 `manager-unavailable` 表示无法查询该管理器，并不证明它管理的软件都没有安装。

缺少 WinGet 时，按照 [App Installer 指引](/winenv/zh/guide/getting-started/#winget-不可用时)处理。Scoop 和 mise 的职责不同，不是损坏的 WinGet 的替代品。

## Profile 无法完成解析

用 `win ls` 和 `win diff` 检查声明。完全相同的声明会合并，不兼容的版本或命令提供者则需要明确选择。自动确认参数不会替你解决冲突。只用 `win use <file-or-URL>` 刷新目标来源，用 `win off <name-or-id>` 停用不需要的层；停用不会卸载软件。

## 哈希、签名或来源校验失败

先停止执行。确认文件来自预期发布者，并通过独立可信渠道核对 SHA-256。不要为了运行安装器而禁用签名检查、Windows 防护或 HTTPS 校验。参见[目录外的软件](/winenv/zh/guide/manual-installers/)和[安全政策](https://github.com/YangYuS8/winenv/blob/main/SECURITY.zh-CN.md)。

## 寻求帮助

选择[使用问题或缺陷表单](https://github.com/YangYuS8/winenv/issues/new/choose)，提供 `win ver`、Windows build、PowerShell 版本、完整命令、预期与实际表现，以及去除敏感信息的文本输出。删除用户名、私人路径、令牌和私有 Profile URL。安全漏洞应走私密报告渠道，不应发到公开 Issue。
