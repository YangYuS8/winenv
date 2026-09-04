---
title: 第一次使用
description: 在现有 Windows 上先做只读检查，再按需完成一次软件安装。
sidebar:
  order: 2
---

本教程假定你已经[安装 Winenv](/winenv/zh/guide/getting-started/)。不需要重装 Windows，也不需要先导入别人的 Profile。

## 1. 检查工具是否就绪

打开一个新的普通 PowerShell 窗口：

```powershell
win ver
win check
```

第一条命令显示 Winenv 版本，第二条检查管理器和命令冲突。缺少可选管理器不代表需要重装系统。必需命令无法运行时，先看[故障排查](/winenv/zh/guide/troubleshooting/)。

## 2. 只查看，不修改

```powershell
win scan
win diff
```

`scan` 查看电脑上的安装记录；`diff` 对比当前声明与安装状态。没有用户 Profile 时，它只检查内置运行层，不会把所有已有软件自动纳入声明。这两条命令都不会安装或卸载软件。

## 3. 搜索并选择来源

```powershell
win find ripgrep
```

搜索结果保留管理器和来源信息，不要仅凭相似名称做决定。此例中，如果 Scoop 的 main 目录提供 ripgrep，可以检查这个准确的来源标识：

```powershell
win show scoop:main/ripgrep
win add scoop:main/ripgrep -n
```

预演会显示计划，必要时也包括管理器准备步骤。如果该来源不可用，请先检查管理器，不要随意换成不相关的软件。

## 4. 按需执行计划

只有在你确实需要 ripgrep，并接受显示的来源后，才运行：

```powershell
win add scoop:main/ripgrep
```

阅读前置软件与信任确认提示。这一步会修改电脑，前面的检查不会。已经存在的兼容安装可能被直接复用。单独安装软件也不等于导入了一个共享 Profile。

你已经掌握日常流程：检查、搜索、选择来源、预演、执行。接下来可以阅读[软件管理](/winenv/zh/guide/packages/)或 [Profile 概念](/winenv/zh/concepts/profiles-and-ownership/)。
