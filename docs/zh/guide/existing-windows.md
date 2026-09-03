# 接入现有 Windows

不需要重装系统，也不需要让 Winenv 把现有软件重新安装一遍。

## 先做只读扫描

安装 Winenv 后执行：

```powershell
win scan
win scan powertoys       # 按关键词过滤
win scan -From winget    # 按管理器过滤
```

扫描不会安装、升级、卸载或写入 Profile。结果分为三类：

| 状态 | 含义 |
| --- | --- |
| `managed` | 已经被某个启用的 Winenv Profile 声明 |
| `adoptable` | 当前安装能映射到 WinGet 软件源、Scoop bucket 或 mise 工具，可在另一台机器复现 |
| `local` | Windows 知道它已安装，但当前目录无法可靠映射，例如部分 OEM 工具和手工安装软件 |

`winget list` 能列出由 WinGet 和其他方式安装的应用。因此结果中的 `winget` 表示“当前能由这个目录复现”，不代表 Winenv 声称软件最初由 WinGet 安装。

## 选择性纳入基线

```powershell
win adopt
win adopt powertoys
win adopt -From scoop
win adopt -n             # 选择并预览，不写入
```

`adopt` 只允许选择 `adoptable` 项，并把选择合并到：

```text
%LOCALAPPDATA%\Winenv\profiles\adopted.json
```

这个过程不会重新安装、升级或卸载软件。重复执行只合并新选择；mise 会保留当前声明的版本，Scoop 会尽量记录自定义 bucket 的 HTTPS 来源。

Winenv 无法可靠猜测每个包提供的命令，因此自动生成项的 `commands` 会留空。准备长期分享时，可以复制这份 JSON，补充名称、分组与命令，再用 `win use <文件>` 导入正式 Profile。

## 无法映射的软件

`local` 项不会被强行写进“可复现”清单：

- 若它登记在 Windows“已安装的应用”中，通常仍可通过 `win rm` 查找和卸载；
- 若以后能与 WinGet 公共目录匹配，便可由 WinGet 接管更新；
- 否则继续使用软件自身更新器，或重新运行新版安装器。

这样可以接管能可靠描述的部分，同时不为未知软件编造升级和卸载规则。

## 停用自动生成的 Profile

```powershell
win off adopted
```

软件和快照都会保留，只撤销这层声明。以后再次运行 `win adopt` 时，Winenv 会先提示并重新启用完整快照。
