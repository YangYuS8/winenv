# 命令速查

日常只需要记住 `win`。完整动作名仍兼容旧脚本，但表中优先列出短命令。

## 软件

| 命令 | 用途 |
| --- | --- |
| `win [软件]` | 打开交互选择器，可直接带搜索词 |
| `win find <软件>` | 只打印三个管理器的搜索结果 |
| `win show <软件>` | 显示包来源、归属和详情 |
| `win add [软件]` | 应用当前 Profile，或安装指定软件/文件 |
| `win up` | 更新 Winenv 和管理器中登记的软件 |
| `win rm [软件]` | 选择或搜索并卸载软件 |
| `win clean` | 清理 Scoop 缓存和未引用的旧工具版本 |

## Profile 与现有系统

| 命令 | 用途 |
| --- | --- |
| `win scan [软件]` | 只读扫描当前机器的软件 |
| `win diff [软件]` | 比较最终 Profile 声明与实际安装状态，不修改任何一方 |
| `win adopt [软件]` | 选择可复现软件，合并到本机 `adopted` Profile |
| `win use <文件或 URL>` | 导入、刷新并安装一个独立 Profile |
| `win use` | 列出已经登记的 Profile |
| `win off [Profile]` | 停用一层声明，不卸载软件 |
| `win ls` | 查看 Profile、有效软件与引用关系 |

## 来源、语言与诊断

| 命令 | 用途 |
| --- | --- |
| `win bucket` | 列出 Scoop bucket |
| `win bucket <名称> [HTTPS URL]` | 添加已知或第三方 bucket |
| `win lang [en\|zh\|auto]` | 查看或持久设置界面语言 |
| `win check` | 检查管理器、运行能力和命令冲突 |
| `win ver` | 显示 Winenv 版本 |
| `win help` | 显示终端帮助 |

## 常用参数

| 短参数 | 完整形式 | 用途 |
| --- | --- | --- |
| `-From` | `-Manager` | 限定 `managed`、`winget`、`scoop` 或 `mise` |
| `-P` | `-Profiles` | 临时选择 Profile 分组 |
| `-Lang` | `-Language` | 为本次执行选择 `en`、`zh` 或 `auto` |
| `-n` | `-DryRun` | 只生成计划，不改变系统 |
| `-y` | `-Yes` | 自动确认普通操作 |
| `-Hash` | `-Sha256` | 校验本地安装器 SHA-256 |
| `-Args` | `-InstallerArguments` | 把明确知道的参数传给 EXE/MSI |

## 来源令牌示例

```powershell
win add winget:winget/Microsoft.VisualStudioCode
win add scoop:extras/powertoys
win add mise:node
```

从 `win` 或 `win find` 的结果复制令牌最稳妥，因为它包含了实际管理器和仓库来源。

## 兼容的完整动作名

这些名称继续可用，主要用于已有脚本：

| 短命令 | 完整动作 |
| --- | --- |
| `ls` | `list` |
| `off` | `unuse` |
| `find` | `search` |
| `show` | `info` |
| `check` | `doctor` |
| `add` | `install` |
| `up` | `update` |
| `rm` | `remove` |
| `clean` | `cleanup` |
| `lang` | `language` |
| `ver` | `version` |

不带动作的 `win` 等同于交互式 `store`。
