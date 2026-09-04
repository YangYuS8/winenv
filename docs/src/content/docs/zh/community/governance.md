---
title: "项目治理"
description: "Winenv 文档：项目治理。"
sidebar:
  order: 3
---

<span id="项目治理"></span>

Winenv 目前由维护者主导，以轻量而有记录的方式作出决定。完整规范见 [`GOVERNANCE.zh-CN.md`](https://github.com/YangYuS8/winenv/blob/main/GOVERNANCE.zh-CN.md)。

## 决策方式

常规修复和文档修改通过 Pull Request 评审决定。涉及包归属、Profile 语义、安全边界、兼容性或自动化的修改，应先创建 Issue，说明：

- 具体用户问题；
- 考虑过的方案；
- 安全和信任影响；
- 向后兼容与迁移；
- 持续维护成本。

维护者会尽量寻求大致共识。如果无法达成，会根据项目范围、安全、可维护性、兼容性和用户收益作出决定，并在隐私与安全允许时公开记录理由。

## 角色与发布

用户、贡献者、评审者和维护者通过持续、建设性的工作获得逐步增加的责任。权限遵循最小化原则。当前首席维护者是 [YangYuS8](https://github.com/YangYuS8)。

只有仓库自动化会发布官方版本、tag、校验和和 Pages 部署。最新稳定 Release 是受支持通道。

## 问责

贡献者应披露重大利益冲突，并在条件允许时退出最终评审。赞助不会购买路线图优先级。社区行为遵循[行为准则](https://github.com/YangYuS8/winenv/blob/main/CODE_OF_CONDUCT.zh-CN.md)，漏洞使用[私下安全流程](https://github.com/YangYuS8/winenv/blob/main/SECURITY.zh-CN.md)。
