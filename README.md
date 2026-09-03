# Winenv

[![CI](https://github.com/YangYuS8/winenv/actions/workflows/ci.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/ci.yml)
[![Release](https://github.com/YangYuS8/winenv/actions/workflows/release.yml/badge.svg)](https://github.com/YangYuS8/winenv/actions/workflows/release.yml)
[![GitHub Release](https://img.shields.io/github/v/release/YangYuS8/winenv)](https://github.com/YangYuS8/winenv/releases/latest)

这是一个先服务于个人使用的 Windows 11 软件管理层。它不修改 Windows 镜像，也不试图替代 WinGet、Scoop 或 mise；它把三者组织成一个稳定入口，同时把软件目录和安装状态交还给各管理器维护。

Winenv 自己不建立第四套软件仓库：

- 搜索时实时查询 WinGet、Scoop 和 mise；
- 同一个软件来自多个管理器时，保留为带来源标记的独立选项；
- 安装清单外的软件不需要先修改 `profile.json`；
- 更新和卸载读取各管理器当前的真实状态；
- `profile.json` 只保存新机需要复现的个人基线和少量明确覆盖。

当前默认清单参考了这台 Omarchy 电脑的实际使用习惯：

- 普通 Windows 应用交给 WinGet；
- 便携命令行工具交给 Scoop；
- 需要版本控制的开发工具交给 mise；
- Scoop 的旧版本由 `win clean` 显式清理，mise 则遵循自身带宽限期的自动清理策略；
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
# 输入关键词后，打开可多选、预览详情的终端应用商店
win store
win store powertoys

# 实时联合搜索 WinGet、Scoop 和 mise，并标出命中的基线项
win search powertoys

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

# 安装基线中的单个软件
win add vscode

# 清单外名称会先联合搜索，再让你选择来源
win add powertoys

# 也可复制 search 返回的令牌，跳过再次选择
win add winget:winget/Microsoft.PowerToys
win add scoop:extras/powertoys

# 只显示将要执行的操作
win add -DryRun

# 从各管理器的已安装清单中搜索并选择卸载
win rm powertoys

# 不带关键词时浏览全部已安装项；令牌可直接定位来源
win rm
win rm scoop:extras/powertoys

# 立即清理 Scoop 旧版本以及 mise 当前未再引用的版本
win clean
```

完整动作名仍然可用，例如 `win update`、`win install` 和 `win remove vscode`。

`store` 是参考 Omarchy 包选择器实现的交互入口：先给出一个查询词，再用 `fzf` 继续模糊筛选；`Tab` 多选、`Enter` 安装、`Alt-P` 切换详情预览、`Alt-J/K` 滚动预览，按 `Esc` 取消。界面中的每一行都显示管理器、仓库来源、名称、ID 和版本。`win browse` 和不带关键词的 `win search` 也会进入同一流程。如果当前只安装了 Winenv 本体而缺少界面依赖，先执行 `win add fzf`。

`search` 不维护容易过期的远程索引，而是把三个管理器的实时结果转换成统一表格。WinGet 和 Scoop 都有同一个软件时，两行都会保留，Winenv 不会静默替你猜一个。每行会给出可直接执行的 `win add` 命令，清单外结果使用包含管理器与仓库的来源令牌；只有希望在下一台新机自动复现的软件，才需要以后加入 `profile.json`。使用 `-Manager managed|winget|scoop|mise` 可以缩小搜索范围。

`update` 会先更新 Winenv 本身，再调用 `winget upgrade --all`、`scoop update *` 和 `mise up`，因此管理器中已经登记、但不在 profile 的软件也会更新。它尊重 WinGet pin、Scoop hold 和 mise 配置。mise 会按自己的宽限期清理已被升级替换、且不再被任何配置引用的旧版本；真正需要保留的版本应在全局或项目 mise 配置中明确指定。`win clean` 只是用于立即执行清理。更新前会展示范围；除非传入 `-Yes`，否则会要求确认。

## 默认 profiles

`profile.json` 是新机基线，不是 Winenv 的软件目录。默认启用：

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

## 默认归属策略

安装任何新软件前，按下面的顺序判断：

1. 是否需要针对不同项目切换版本？是则归 mise。
2. 是否只是解压后运行的用户级 CLI？是则归 Scoop。
3. 是否需要 Windows 安装器、服务、注册表、文件关联或系统集成？是则归 WinGet。
4. 如果三个来源都不适合，才登记为 `vendor` 例外。

这套顺序是个人默认策略，不是需要人工维护的完整映射表。搜索结果始终保留实际来源，由你在安装时做最后选择。只有写入个人基线的包需要遵守“一个命令一个默认所有者”；`doctor` 会检查基线内的冲突，并展示 Windows 当前实际解析到的全部路径。

## 目录

```text
winenv/
├── install.ps1          # 一行安装和自更新入口
├── win.ps1              # 核心命令
├── VERSION              # Actions 自动维护的版本
├── profile.json         # 新机个人基线及少量归属覆盖
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
- 绕过各包管理器自身的保留、pin、hold 或清理策略。

这些能力只有在个人使用稳定之后，才值得逐项加入。

## License

[MIT](./LICENSE)
