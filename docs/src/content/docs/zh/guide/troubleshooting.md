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

<span id="network-and-proxy"></span>

## 网络与代理

下载超时或连接失败时，先看原始错误。命令失败不代表一定需要代理：软件不存在、权限不足、请求限流和校验失败都有其他原因。连接正常就不用配置。

Winenv 不管理代理、不切换镜像，也不会换条线路自动重试。只对出问题的工具，按其当前帮助和官方说明自行配置：

- **WinGet**：参考 [Microsoft 设置文档](https://learn.microsoft.com/en-us/windows/package-manager/winget/settings)。可用代理选项取决于安装版本和管理员策略。
- **Scoop**：运行 `scoop help config`，查看[代理设置说明](https://github.com/ScoopInstaller/Scoop/blob/master/libexec/scoop-config.ps1)。Scoop 默认使用 Internet 选项；Git 等下载辅助工具可能需要单独检查。
- **mise**：按照 [HTTP 代理 FAQ](https://mise.jdx.dev/faq.html#how-do-i-use-mise-with-http-proxies) 配置 `http_proxy` / `https_proxy`；插件的行为可能不同。
- **Winenv 安装脚本或共享文件下载**：使用的是 PowerShell，不是包管理器。查看对应 PowerShell 版本的 [Invoke-WebRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) 和 `Invoke-RestMethod` 帮助。最开始的 `irm ... | iex` 下载失败时，Winenv 尚未启动，无法显示自己的提示。

使用 FlClash 或 Clash Verge 时，先确认客户端正在运行，手动填写的地址和端口与客户端一致。“系统代理”只影响遵循该设置的程序；TUN 在网络层路由流量。关闭工具自己的显式代理不等于绕过 TUN。这些选择仍由代理客户端管理，参见 [Clash Verge 指引](https://www.clashverge.dev/guide/quickstart.html)。

不要关闭 HTTPS、哈希或签名校验。分享日志前删除代理凭据和私有 URL。

## Profile 无法完成解析

用 `win ls` 和 `win diff` 检查声明。完全相同的声明会合并，不兼容的版本或命令提供者则需要明确选择。自动确认参数不会替你解决冲突。只用 `win use <file-or-URL>` 刷新目标来源，用 `win off <name-or-id>` 停用不需要的层；停用不会卸载软件。

## 哈希、签名或来源校验失败

先停止执行。确认文件来自预期发布者，并通过独立可信渠道核对 SHA-256。不要为了运行安装器而禁用签名检查、Windows 防护或 HTTPS 校验。参见[目录外的软件](/winenv/zh/guide/manual-installers/)和[安全政策](https://github.com/YangYuS8/winenv/blob/main/SECURITY.zh-CN.md)。

## 寻求帮助

选择[使用问题或缺陷表单](https://github.com/YangYuS8/winenv/issues/new/choose)，提供 `win ver`、Windows build、PowerShell 版本、完整命令、预期与实际表现，以及去除敏感信息的文本输出。删除用户名、私人路径、令牌和私有 Profile URL。安全漏洞应走私密报告渠道，不应发到公开 Issue。
