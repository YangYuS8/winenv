# 目录外的软件

软件不在三个默认目录中时，优先寻找发布者维护的包来源；只有没有可复现元数据时，才把裸 EXE/MSI 当作一次安全交接。

## Scoop 扩展 bucket

默认 bucket 没有某个软件时，可以添加 Scoop 已知 bucket 或可信的第三方 Git 仓库：

```powershell
win bucket                         # 查看已启用 bucket
win bucket extras                  # Scoop 已知 bucket
win bucket mybucket https://github.com/user/scoop-bucket.git
```

第三方 bucket 中的 manifest 可以包含安装脚本，因此它属于新的信任边界。Winenv 会显示完整来源；首次添加、同名 bucket 更换 URL 都必须人工确认，`-y` 不会替你做这个决定。

需要跨机器复现时，可在 Profile 中声明：

```json
{
  "scoopBuckets": [
    "extras",
    {
      "name": "mybucket",
      "url": "https://github.com/user/scoop-bucket.git"
    }
  ]
}
```

同名但 URL 不同的声明会作为冲突停止处理。

## 独立 Scoop manifest

发布者只提供一个 JSON manifest 时：

```powershell
win add C:\Users\me\Downloads\my-app.json
win add https://example.com/my-app.json
```

Winenv 只接受本地或 HTTPS `.json`，大小限制为 1 MiB。安装前会显示来源、版本以及实际快照的 SHA-256，确认后仍由 Scoop 完成安装登记。

独立 manifest 没有稳定更新源。长期使用并希望 `scoop update` 自动发现版本时，应将它放进自己或可信维护者的 bucket。

## 原始 EXE 与 MSI

```powershell
win add C:\Users\me\Downloads\setup.exe
win add C:\Users\me\Downloads\setup.msi
```

运行前会展示文件大小、产品版本、SHA-256、Authenticode 状态和发布者。EXE 使用发布者原本的界面；MSI 通过 Windows 自带的 `msiexec.exe` 运行，默认添加 `/norestart`，详细日志写入 `%LOCALAPPDATA%\Winenv\logs`。

Winenv 不猜测并不存在统一标准的 `/S`、`/silent` 参数。已经从可信来源取得参数或哈希时，可以明确传入：

```powershell
win add .\setup.exe -Args '/S','/norestart'
win add .\setup.msi -Args '/passive','INSTALLDIR=C:\Tools\Example'
win add .\setup.exe -Hash 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

`-y` 只会自动接受有效 Authenticode 签名的安装器，或通过 `-Hash` 精确校验的未签名文件。哈希不匹配始终停止；签名损坏、不受信任或无法验证时仍要求人工查看。

Winenv 暂不直接下载 EXE/MSI。裸安装器也不会被伪装成新的包管理器：后续能否升级、卸载或静默运行仍取决于发布者。

## 本地 WinGet manifest

需要稳定复现时，优先制作包含下载地址、SHA-256、参数和版本信息的 WinGet manifest：

```powershell
win add C:\Users\me\manifests\Example.App.yaml
win add C:\Users\me\manifests\Example.App
```

Winenv 会列出 YAML 文件及 SHA-256，确认后执行 `winget validate` 和 `winget install --manifest`。多文件 manifest 直接传入目录。

本地 manifest 是管理员控制的 WinGet 能力。第一次使用前，需要在管理员 PowerShell 中明确启用：

```powershell
winget settings --enable LocalManifestFiles
```

Winenv 会检测该设置，但不会自行提权或静默修改它。

## 安装后的管理

只要安装器把应用登记到 Windows“已安装的应用”，之后通常可以使用：

```powershell
win rm 应用名
```

只有当已安装应用能够匹配 WinGet 公共目录时，`win up` 才能替它升级；否则继续使用软件自带更新器或新版安装器。
