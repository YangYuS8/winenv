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
- 内置 `profile.json` 只保存 Winenv 正常运行所需的软件；个人选择放在独立用户 profile 中。

用户可以在自己的 profile 中采用类似 Omarchy 的默认归属策略：

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
5. 只安装 `profile.json` 中的 Winenv 运行依赖：PowerShell 7 和 fzf。

如果已经准备了用户 profile，可以在首次安装时从本地文件或 HTTPS 链接导入：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -UserProfile C:\Users\me\my-winenv.json
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -UserProfile https://example.com/my-winenv.json
```

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
# 打开终端应用商店；也可以直接输入软件名
win
win powertoys
win vscode -From winget

# 只打印搜索结果，不打开选择界面
win find powertoys

# 应用当前 profile，或者安装一个已知软件
win add
win add vscode
win add scoop:extras/powertoys

# 本地和线上 profile 可以同时启用；停用不会卸载软件
win use C:\Users\me\my-winenv.json
win use https://example.com/my-winenv.json
win off my-winenv

# 更新、卸载和清理
win up
win rm powertoys
win rm
win clean

# 查看当前配置，检查环境
win ls
win check

# 查看版本和简明帮助
win ver
win help

# 常用短参数：限定来源、只预览、自动确认
win node -From mise
win up -n
win up -y
```

主界面只需要记住上面这些短命令。原有的 `store/search/install/update/remove/doctor/unuse` 等完整动作名仍然兼容已有脚本，但不再作为日常入口推荐。

直接运行 `win` 会进入参考 Omarchy 包选择器实现的交互入口；`win <软件名>` 会带着关键词直接进入。随后用 `fzf` 模糊筛选；`Tab` 多选、`Enter` 安装、`Alt-P` 切换详情预览、`Alt-J/K` 滚动预览，按 `Esc` 取消。界面中的每一行都显示管理器、仓库来源、名称、ID 和版本。如果当前只安装了 Winenv 本体而缺少界面依赖，先执行 `win add fzf`。

`find` 不维护容易过期的远程索引，而是把三个管理器的实时结果转换成统一表格。WinGet 和 Scoop 都有同一个软件时，两行都会保留，Winenv 不会静默替你猜一个。每行会给出可直接执行的 `win add` 命令，清单外结果使用包含管理器与仓库的来源令牌；只有希望在下一台新机自动复现的软件，才需要以后加入自己的用户 profile。使用 `-From managed|winget|scoop|mise` 可以缩小搜索范围。

`up` 会先更新 Winenv 本身，再调用 `winget upgrade --all`、`scoop update *` 和 `mise up`，因此管理器中已经登记、但不在 profile 的软件也会更新。它尊重 WinGet pin、Scoop hold 和 mise 配置。mise 会按自己的宽限期清理已被升级替换、且不再被任何配置引用的旧版本；真正需要保留的版本应在全局或项目 mise 配置中明确指定。`win clean` 只是用于立即执行清理。更新前会展示范围；除非传入 `-y`，否则会要求确认。

## Profile 分层

`profile.json` 是不可掺入个人偏好的运行时层，默认只有：

- PowerShell 7：稳定运行命令及详情预览；
- fzf：提供交互式搜索、选择和卸载界面。

用户可以按同一 schema 在仓库外编写 JSON。它既可以只留在自己电脑上，也可以放在 GitHub、Gist 或自己的站点上分享：

```powershell
win use C:\Users\me\my-winenv.json
win use https://raw.githubusercontent.com/user/dotfiles/main/winenv.json
```

`win use` 会校验 profile，把它作为一个独立声明加入当前机器，展示所有启用 profile 合成后的安装计划并请求确认，然后完成快照保存和安装。它不会覆盖已经启用的其他 profile。同一来源再次执行 `win use` 只刷新自己的快照，不会新建重复项；远程 profile 只接受 HTTPS，并且不会随 `win up` 悄悄刷新，想采用上游的新内容时再次执行原来的 `win use <url>` 即可。

每个快照保存在 `%LOCALAPPDATA%\Winenv\profiles`，注册状态和本机做出的冲突选择保存在 `%LOCALAPPDATA%\Winenv\config.json`。合成遵循几条简单规则：

- 管理器、来源、包 ID 和版本都相同的项只安装一次，但会显示所有 profile 的声明；
- 同一个包要求不同版本，或者两个不同包声明同一个命令时，必须在本机明确选择，Winenv 不按导入顺序猜测；
- `-y` 和 `-n` 遇到尚未解决的冲突会停止，不会静默采用某一方；
- 运行时 profile 始终保留，避免共享配置破坏 Winenv 自己所需的 PowerShell 和 fzf。

`win use` 不带参数会列出所有已登记 profile；传入已保存的名称或 ID 会直接从本机快照重新启用，不需要再次输入 URL。只有传入文件或 HTTPS URL 才会刷新快照。多个 profile 同名时可以使用 `win ls` 显示的 ID 精确指定：

```powershell
win use
win use shared-tools
win off shared-tools
win off shared-tools-e06532a770
```

`win off <profile>` 只撤销这个 profile 的声明并重新计算引用：重复软件若仍被其他 profile 声明就继续受引用，否则标记为 unclaimed。无论哪种情况，它都保留已经安装的软件和 profile 快照。实际软件始终归 WinGet、Scoop 或 mise 管理；确认不再需要后使用 `win rm <software>` 显式卸载。`win clean` 只清理 Scoop 旧版本、缓存和未被 mise 配置引用的工具版本，不会把 unclaimed 软件当垃圾自动删除。

Winenv 官方仓库和 Release 不携带维护者个人清单，也不需要维护一份社区 profile 目录。任何人都可以独立发布自己的配置并分享链接；使用者可以同时组合自己的配置和多个社区配置，不需要把其中任何一份复制进 Winenv 仓库。

profile 中默认启用的 mise 工具会写入 mise 自己会读取的独立片段 `%USERPROFILE%\.config\mise\conf.d\winenv.toml`。Winenv 不修改你的全局 `config.toml`；停用 profile 后只重算这个生成文件，因此项目级和个人全局 mise 配置仍然独立。

可在命令行临时选择 profiles：

```powershell
win add -P base,desktop,development
```

这里的 `-P`（完整形式为 `-Profiles`）只从当前有效的“运行时层 + 用户层”中选择分组，不会改变已激活的用户 profile。

## 默认归属策略

安装任何新软件前，按下面的顺序判断：

1. 是否需要针对不同项目切换版本？是则归 mise。
2. 是否只是解压后运行的用户级 CLI？是则归 Scoop。
3. 是否需要 Windows 安装器、服务、注册表、文件关联或系统集成？是则归 WinGet。
4. 如果三个来源都不适合，才登记为 `vendor` 例外。

这套顺序是个人默认策略，不是需要人工维护的完整映射表。搜索结果始终保留实际来源，由你在安装时做最后选择。只有写入个人基线的包需要遵守“一个命令一个默认所有者”；`win check` 会检查基线内的冲突，并展示 Windows 当前实际解析到的全部路径。

## 目录

```text
winenv/
├── install.ps1          # 一行安装和自更新入口
├── win.ps1              # 核心命令
├── VERSION              # Actions 自动维护的版本
├── profile.json         # 仅包含 Winenv 运行依赖
├── profile.schema.json  # 清单结构
├── migrations/          # 只执行一次的演进脚本
├── scripts/             # 测试和发布资产构建
└── .github/workflows/   # CI 与自动发布
```

运行状态保存在：

```text
%LOCALAPPDATA%\Winenv\state.json
%LOCALAPPDATA%\Winenv\config.json
%LOCALAPPDATA%\Winenv\profiles\*.json
%USERPROFILE%\.config\mise\conf.d\winenv.toml
```

`state.json` 只记录已执行的 migration；`config.json` 记录 profile 注册表和本机冲突选择；`profiles` 保存稳定快照；`winenv.toml` 是根据当前有效声明生成的 mise 配置片段。它们都不存储密码或登录状态。旧版单一 `user-profile.json` 会在首次运行时迁移成独立快照，原文件保留不删。

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
