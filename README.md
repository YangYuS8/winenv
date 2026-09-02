# Winenv

这是一个先服务于个人使用的 Windows 11 软件管理层。它不修改 Windows 镜像，也不试图替代 WinGet、Scoop 或 mise；它只负责规定每类软件归谁管理，并提供一个稳定入口。

当前默认清单参考了这台 Omarchy 电脑的实际使用习惯：

- 普通 Windows 应用交给 WinGet；
- 便携命令行工具交给 Scoop；
- 需要版本控制的开发工具交给 mise；
- Scoop 清理和 mise 旧版本清理不会混在普通更新中自动执行；
- 系统演进通过一次性 migration 脚本完成。

## 第一次使用

在一台新的 Windows 11 上，先克隆仓库：

```powershell
git clone https://github.com/YangYuS8/winenv.git
cd winenv
```

然后在普通 PowerShell 窗口中执行：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
./win.ps1 list
./win.ps1 doctor
./win.ps1 install
```

这是唯一一次需要输入完整脚本名。安装完成并重新打开 PowerShell 后，会得到全局的短命令 `win`。

`install` 会：

1. 检查 Windows 自带的 WinGet；
2. 使用 WinGet 安装 mise；
3. 在确实需要 Scoop 时，显示 Scoop 官方安装脚本的 SHA-256，并在执行前询问；
4. 按 `profile.json` 安装默认 profiles 中的软件；
5. 为 Windows PowerShell 和 PowerShell 7 写入幂等的 mise 激活区块；
6. 执行尚未应用的 migrations。

如需无人值守确认 Scoop 官方安装脚本，可加 `-Yes`：

```powershell
./win.ps1 install -Yes
```

## 日常使用

```powershell
# 查看归属和当前选中的 profiles
win ls

# 检查管理器、清单冲突以及命令解析路径
win doctor

# 预览并统一更新
win up

# 安装额外的 editor profile
win add -Profiles editor

# 只显示将要执行的操作
win add -DryRun

# 通过清单中的唯一所有者卸载一个软件
win rm vscode

# 显式清理 Scoop 和 mise 保留的旧版本
win clean
```

完整动作名仍然可用，例如 `win update`、`win install` 和 `win remove vscode`。

`update` 会依次处理 WinGet、Scoop、mise 和 migrations，但只更新当前 profiles 中登记的软件，也不会自动删除旧版本。更新前会展示这次受管理的更新范围；除非传入 `-Yes`，否则会要求确认。

## 默认 profiles

`profile.json` 默认启用：

- `base`：PowerShell、Windows Terminal、Git；
- `desktop`：Chrome、Obsidian；
- `china`：QQ、微信、FlClash；
- `gaming`：Steam；
- `cli`：与当前 Omarchy `/usr/bin` 工具相近的便携 CLI；
- `development`：与当前 mise 配置相近的开发工具。

`editor` 中的 VS Code 目前是可选项。

可在命令行临时选择 profiles：

```powershell
./win.ps1 install -Profiles base,desktop,development
```

也可以直接修改 `profile.json` 中的 `defaultProfiles`。

## 软件归属规则

安装任何新软件前，按下面的顺序判断：

1. 是否需要针对不同项目切换版本？是则归 mise。
2. 是否只是解压后运行的用户级 CLI？是则归 Scoop。
3. 是否需要 Windows 安装器、服务、注册表、文件关联或系统集成？是则归 WinGet。
4. 如果三个来源都不适合，才登记为 `vendor` 例外。

不要在不同管理器中登记同一个命令。`doctor` 会检查清单内的命令所有权冲突，并展示 Windows 当前实际解析到的全部路径。

## 目录

```text
winenv/
├── win.ps1              # 首次安装入口
├── profile.json         # 软件及其唯一所有者
├── profile.schema.json  # 清单结构
└── migrations/          # 只执行一次的演进脚本
```

运行状态保存在：

```text
%LOCALAPPDATA%\Winenv\state.json
```

这个文件只记录已执行的 migration，不存储密码或登录状态。

## 当前边界

这是第一个可执行版本，刻意不包含：

- 删除 Windows 内置组件；
- 修改 Defender、BitLocker、Windows Update 策略；
- 自动安装驱动；
- 保存登录令牌和软件私有数据；
- 自动清理所有旧版本。

这些能力只有在个人使用稳定之后，才值得逐项加入。

## License

[MIT](./LICENSE)
