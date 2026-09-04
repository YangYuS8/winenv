---
title: "查找与管理软件"
description: "Winenv 文档：查找与管理软件。"
sidebar:
  order: 3
---

<span id="查找与管理软件"></span>

Winenv 不维护自己的软件索引。每次搜索都查询当前可用的 WinGet、Scoop 和 mise 目录，再把结果整理成统一界面。

## 终端软件选择器

```powershell
win                 # 浏览和筛选
win powertoys       # 带关键词打开
win vscode -From winget
```

选择器由 fzf 提供：

- 输入文字进行模糊筛选；
- `Tab` 多选，`Enter` 安装，`Esc` 取消；
- `Alt-P` 切换详情预览；
- `Alt-J` / `Alt-K` 滚动预览。

每一行都显示管理器、仓库来源、名称、ID 和版本。同一个软件同时存在于多个目录时会保留为多条独立选项，Winenv 不会静默替你决定。

只需要可复制的文本结果时：

```powershell
win find powertoys
win find node -From mise
```

## 安装与复用

```powershell
win add                 # 应用所有启用 Profile
win add vscode          # 安装一个已知软件
win add scoop:extras/powertoys
win add mise:node
```

清单外的搜索结果会带有管理器与来源令牌，可直接交给 `win add`。只有希望在下一台电脑自动复现的软件，才需要加入自己的 Profile。

安装前 Winenv 会读取各管理器当前的真实库存。包和版本已经满足时显示 `reuse` 并原地复用，不重复安装。

## 默认归属策略

决定自己的长期基线时，依次问：

1. 是否需要针对不同项目切换版本？是则用 mise。
2. 是否只是解压即可使用的用户级 CLI？是则用 Scoop。
3. 是否需要安装器、服务、注册表、文件关联或系统集成？是则用 WinGet。
4. 三者都不合适时，再作为手工安装例外处理。

这套规则只帮助个人做出一致选择。搜索结果仍展示所有真实来源。

## 更新

```powershell
win up
```

它会先更新 Winenv，再依次更新 WinGet、Scoop 和 mise 当前登记的软件，因此也涵盖不在 Profile 中的包。WinGet pin、Scoop hold 与 mise 配置仍由各管理器自己解释。

默认会先展示范围并确认；自动化中可以使用 `win up -y`。

## 卸载

```powershell
win rm                 # 交互选择已安装软件
win rm powertoys       # 按关键词缩小范围
```

实际卸载仍由登记该软件的 WinGet、Scoop 或 mise 执行。停用 Profile 不等于卸载，详见 [Profile 的引用关系](/winenv/zh/guide/profiles/#停用与软件归属)。

## 清理旧版本

```powershell
win clean
```

`win clean` 会清理 Scoop 旧版本和缓存，并要求 mise 清理不再被任何 mise 配置引用的工具版本。需要保留的旧版本应在全局或项目 mise 配置中明确指定。

## 预览与自动确认

常用短参数：

```powershell
win add node -From mise   # 限定管理器
win up -n                 # dry-run，只预览
win up -y                 # 自动确认普通操作
```

第三方源和无法验证的安装器属于新的信任决定，不会被 `-y` 静默接受。
