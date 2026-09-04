# 组合 Profile

Profile 是“希望这台电脑具备什么”的声明，不是另一套包数据库。实际安装、升级和卸载仍由 WinGet、Scoop 或 mise 完成。

## 内置运行层

仓库中的 `profile.json` 只保存 Winenv 正常运行所需的能力：

- PowerShell 7：稳定执行命令和详情预览；
- fzf：交互搜索、选择与卸载界面。

这两项不是所有权声明。机器上已有的兼容版本会被直接复用，Winenv 不会因为它出现在运行层就改变原本的更新方式。

维护者的个人软件不会放进开源仓库或 Release。

## 使用自己的或社区的 Profile

用户 Profile 使用与 `profile.json` 相同的 schema，可以留在本地，也可以通过 GitHub、Gist 或自己的站点分享：

```powershell
win use C:\Users\me\my-winenv.json
win use https://raw.githubusercontent.com/user/dotfiles/main/winenv.json
```

`win use` 会校验文件、保存独立快照、展示所有启用 Profile 合成后的计划，然后请求确认。它不会覆盖其他 Profile。

同一来源再次导入只刷新自己的快照，不产生重复层。远程 Profile 只接受 HTTPS，并且不会在 `win up` 时悄悄更新；想采用上游新内容时，需要再次执行原来的 `win use <url>`。

## 最小示例

```json
{
  "$schema": "https://raw.githubusercontent.com/YangYuS8/winenv/main/profile.schema.json",
  "schemaVersion": 1,
  "name": "my-tools",
  "defaultProfiles": ["desktop", "development"],
  "scoopBuckets": ["extras"],
  "packages": [
    {
      "key": "vscode",
      "displayName": "Visual Studio Code",
      "owner": "winget",
      "id": "Microsoft.VisualStudioCode",
      "source": "winget",
      "profiles": ["development"],
      "commands": ["code"]
    },
    {
      "key": "node",
      "displayName": "Node.js",
      "owner": "mise",
      "id": "node",
      "version": "lts",
      "profiles": ["development"],
      "commands": ["node", "npm"]
    }
  ]
}
```

完整字段约束以仓库中的 [`profile.schema.json`](https://github.com/YangYuS8/winenv/blob/main/profile.schema.json) 为准。

## 合并与冲突

Winenv 先合成全部启用层，再执行安装：

- 管理器、来源、包 ID 和版本相同的声明只安装一次，同时保留所有 Profile 的引用；
- 同一个包要求不同版本，或不同包声明同一个命令时，必须在本机明确选择；
- `-y` 与 `-n` 遇到未解决冲突会停止，不按导入顺序猜测；
- 内置运行层始终保留，社区配置不能破坏 Winenv 依赖的 PowerShell 与 fzf。

本机冲突选择保存在 `%LOCALAPPDATA%\Winenv\config.json`，不会被写回别人的 Profile。

## 查看与重新启用

```powershell
win use                 # 列出已登记 Profile
win ls                  # 查看 Profile 和最终有效软件
win diff                # 比较最终声明与这台电脑
win diff node           # 按软件名、键或 ID 限定比较范围
win use shared-tools    # 从本机快照重新启用
```

只有传入文件或 HTTPS URL 才会刷新快照。多个 Profile 同名时，使用 `win ls` 显示的 ID 精确指定。

### 理解 `win diff`

`win diff` 始终只读，不会安装、升级、卸载、纳入、刷新或改写 Profile，因此不需要加 `-n` 或 `-y`。可以用 `-P` 临时比较指定分组，也可以用 `-From winget|scoop|mise` 只查看某个管理器。

结果只比较内置运行层与已启用用户 Profile 合成后的有效声明：

| 状态 | 含义 |
| --- | --- |
| `已满足` | 所需运行能力或精确的软件包身份存在，且已声明版本兼容 |
| `缺失` | 管理器可用，但声明的软件包没有安装 |
| `版本偏差` | 软件包存在，但版本不满足声明 |
| `来源偏差` | 同一管理器中存在相同包 ID，但 WinGet source 或 Scoop bucket 不同 |
| `管理器不可用` | 负责的管理器缺失、损坏，或无法提供清单 |
| `无法验证` | Winenv 找到了声明，但无法安全确认状态，例如发布者安装器或未知的已安装版本 |

没有固定版本的声明只表示“已安装”；`diff` 不查询远程目录来判断它是不是最新版本。当前 Profile 之外额外安装的软件有意不算偏差，也绝不会成为删除理由；需要查看更完整的现有软件清单时，请使用 `win scan`。

当前命令把结果交给用户审阅，即使有待处理项也会正常返回。自动修复与裁剪明确不属于这条只读边界。

## 停用与软件归属

```powershell
win off shared-tools
win off shared-tools-e06532a770
```

停用只撤销这个 Profile 的声明并重新计算引用：

- 仍被其他 Profile 声明的软件继续显示为受引用；
- 不再被任何 Profile 声明的软件标记为 `unclaimed`；
- 软件本体和 Profile 快照都保留，不自动卸载。

软件始终归实际管理器维护。确认不再需要后，显式执行 `win rm <软件>`。`win clean` 也不会把 `unclaimed` 软件当作垃圾删除。

## mise 配置边界

启用 Profile 中的 mise 工具会生成：

```text
%USERPROFILE%\.config\mise\conf.d\winenv.toml
```

Winenv 不修改个人的全局 `config.toml`。停用 Profile 时只重算自己的片段，因此项目级和个人全局 mise 配置保持独立。

可以临时只应用某些分组：

```powershell
win add -P base,desktop,development
```

`-P` 是 `-Profiles` 的短写，只从当前有效的运行层和用户层选择分组，不改变已启用 Profile。
