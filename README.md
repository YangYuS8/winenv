# Winenv

[![CI](https://github.com/YangYuS8/winenv/actions/workflows/ci.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/ci.yml)
[![Release](https://github.com/YangYuS8/winenv/actions/workflows/release.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/release.yml)
[![GitHub Release](https://img.shields.io/github/v/release/YangYuS8/winenv)](https://github.com/YangYuS8/winenv/releases/latest)

这是一个先服务于个人使用的 Windows 11 软件管理层。它不修改 Windows 镜像，也不试图替代 WinGet、Scoop 或 mise；它只负责规定每类软件归谁管理，并提供一个稳定入口。

当前默认清单参考了这台 Omarchy 电脑的实际使用习惯：

- 普通 Windows 应用交给 WinGet；
- 便携命令行工具交给 Scoop；
- 需要版本控制的开发工具交给 mise；
- Scoop 清理和 mise 旧版本清理不会混在普通更新中自动执行；
- 系统演进通过一次性 migration 脚本完成。

## 第一次使用

在一台新的 Windows 11 上打开普通 PowerShell，执行一条命令：

```powershell
irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1 | iex
```

安装器会自动：

1. 从 GitHub Releases 获取最新稳定版；
2. 下载 `winenv-<version>.zip` 和 `SHA256SUMS`；
3. 校验 SHA-256 后安装到 `%LOCALAPPDATA%\Winenv\versions`；
4. 建立全局短命令 `win`；
5. 按 `profile.json` 应用默认个人环境。

如果只想安装 `win` 命令、暂时不安装清单中的软件：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -ToolOnly
```

也可以安装指定版本：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -Version 0.1.0
```

## 日常使用

```powershell
# 打开可搜索、多选、预览详情的终端应用商店
win store

# 同时搜索 Winenv 清单、WinGet、Scoop 和 mise
win search ripgrep

# 只搜索某一个来源
win search vscode -Manager winget
win find node -Manager mise

# 查看归属和当前选中的 profiles
win ls

# 检查管理器、清单冲突以及命令解析路径
win doctor

# 预览并统一更新
win up

# 查看或只更新 Winenv 本身
win version
win selfup

# 安装额外的 editor profile
win add -Profiles editor

# 安装清单中的单个软件
win add vscode

# 只显示将要执行的操作
win add -DryRun

# 通过清单中的唯一所有者卸载一个软件
win rm vscode

# 显式清理 Scoop 和 mise 保留的旧版本
win clean
```

完整动作名仍然可用，例如 `win update`、`win install` 和 `win remove vscode`。

`store` 是参考 Omarchy 包选择器实现的交互入口：直接输入关键词模糊搜索，用 `Tab` 多选、`Enter` 安装、`Alt-P` 切换详情预览、`Alt-J/K` 滚动预览，按 `Esc` 取消。它只展示 `profile.json` 中已经确认唯一管理器的软件；`win browse` 和不带关键词的 `win search` 也会打开同一个界面。如果当前只安装了 Winenv 本体而缺少界面依赖，先执行 `win add fzf`。

`search` 参考 Omarchy 的包选择器，不自行维护一份容易过期的远程索引：它先显示 `profile.json` 中已经确定归属的软件，再查询各个包管理器的实时目录。清单中的结果会直接给出 `win add <key>`；外部目录结果用于确认准确的包 ID 和应该使用的管理器，再决定是否将它纳入 `profile.json`。使用 `-Manager managed|winget|scoop|mise` 可以缩小搜索范围。

`update` 会先更新 Winenv 本身，再依次处理 WinGet、Scoop、mise 和 migrations。它只更新当前 profiles 中登记的软件，也不会自动删除旧版本。更新前会展示这次受管理的更新范围；除非传入 `-Yes`，否则会要求确认。

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
win add -Profiles base,desktop,development
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
├── install.ps1          # 一行安装和自更新入口
├── win.ps1              # 核心命令
├── VERSION              # Actions 自动维护的版本
├── profile.json         # 软件及其唯一所有者
├── profile.schema.json  # 清单结构
├── migrations/          # 只执行一次的演进脚本
├── scripts/             # 测试和发布资产构建
└── .github/workflows/   # CI 与自动发布
```

运行状态保存在：

```text
%LOCALAPPDATA%\Winenv\state.json
```

这个文件只记录已执行的 migration，不存储密码或登录状态。

## 版本和发布

版本、CHANGELOG、Git tag、GitHub Release、ZIP 和 SHA-256 全部由 GitHub Actions 根据提交记录生成，不手工修改版本号或编写发布日志。

提交信息使用 Conventional Commits：

```text
fix: 修复安装器路径                         # patch
feat: 添加新的软件 profile                  # minor
feat!: 修改不兼容的配置结构                 # major
docs: 补充说明                              # 不发布
chore: 更新维护配置                         # 不发布
```

推送或合并到 `main` 后，Release workflow 会：

1. 验证 JSON schema、软件归属和 PowerShell 语法；
2. 分析上一个 tag 之后的提交；
3. 自动决定下一个语义化版本；
4. 更新 `VERSION` 和 `CHANGELOG.md`；
5. 创建版本提交和 `v<version>` tag；
6. 创建 GitHub Release，并上传 ZIP 与 `SHA256SUMS`。
7. 只有确实发布了新版本时，才从 GitHub Release 下载并执行安装冒烟测试。

因此正常开发只需要写准确的 `feat:`、`fix:` 等提交信息。不会产生新版本的提交仍会接受测试和版本判断，但不会额外启动安装冒烟工作流。

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
