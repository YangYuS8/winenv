# 开始使用

Winenv 支持 Windows 11。首次安装只需要普通 PowerShell、网络连接，以及 Windows 11 通常随 App Installer 提供的 WinGet。

## 一行安装

打开普通 PowerShell，执行：

```powershell
irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1 | iex
```

安装器会自动完成以下工作：

1. 从 GitHub Releases 获取最新稳定版；
2. 下载版本 ZIP 和 `SHA256SUMS` 并校验 SHA-256；
3. 安装到 `%LOCALAPPDATA%\Winenv\versions`；
4. 创建全局短命令 `win`；
5. 探测 PowerShell 7、fzf 和 mise 的真实路径及版本，兼容时直接复用；
6. 只为缺失的运行能力安装内置 Profile 声明的默认包。

安装结束后新开一个 PowerShell 窗口：

```powershell
win check
win
```

::: tip 已经安装过前置软件
只要现有的 PowerShell 7 和 fzf 达到最低版本并且可以正常运行，Winenv 就复用它们。原本通过 MSI、ZIP、Scoop 或其他方式安装的软件仍归原来的方式更新和卸载。
:::

## WinGet 不可用时

WinGet 是 Windows 侧的基础安装通道。找不到 `winget.exe` 时，安装器会先尝试重新注册 Windows 11 自带的 App Installer；仍不可用则停止，并给出 Microsoft Store 和官方修复方向。

Winenv 不会静默提权，也不会为了补 WinGet 擅自安装 PowerShell Gallery 模块。

## 安装时导入自己的 Profile

可以从本地文件或 HTTPS 链接导入：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -UserProfile C:\Users\me\my-winenv.json

& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -UserProfile https://example.com/my-winenv.json
```

Profile 会作为独立的一层加入，不会覆盖内置运行层或其他用户 Profile。详见[组合 Profile](./profiles)。

## 只安装 Winenv

想先获得 `win` 命令、不立即安装 Profile 中的软件：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -ToolOnly
```

之后可随时执行 `win add` 应用当前 Profile。

## 安装指定版本

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -Version 0.12.0
```

不指定 `-Version` 时始终安装最新稳定 Release；日常执行 `win up` 会先更新 Winenv 自身。

## 下一步

- 新电脑：直接[查找与管理软件](./packages)。
- 已经使用一段时间的电脑：先[扫描并接入现有系统](./existing-windows)。
- 有自己的软件基线：创建或导入[用户 Profile](./profiles)。
