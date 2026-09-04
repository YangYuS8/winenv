---
title: "Governance"
description: "Governance for Winenv, the Windows 11 software management layer."
sidebar:
  order: 3
---

<span id="governance"></span>

Winenv is currently maintainer-led, with a lightweight and documented decision process. See the complete [`GOVERNANCE.md`](https://github.com/YangYuS8/winenv/blob/main/GOVERNANCE.md).

## How decisions are made

Routine fixes and documentation changes are decided in pull-request review. Changes to package ownership, profile semantics, security boundaries, compatibility, or automation should begin with an issue describing:

- the concrete user problem;
- considered alternatives;
- security and trust implications;
- backward compatibility and migration;
- ongoing maintenance cost.

The maintainer seeks rough consensus. If consensus is not possible, the lead maintainer decides using project scope, safety, maintainability, compatibility, and user benefit, and records the reason publicly when privacy and security allow.

## Roles and releases

Users, contributors, reviewers, and maintainers gain increasing responsibility through sustained constructive work. Permissions follow least privilege. The current lead maintainer is [YangYuS8](https://github.com/YangYuS8).

Only repository automation publishes official versions, tags, checksums, and Pages deployments. The latest stable release is the supported channel.

## Accountability

Contributors disclose material conflicts of interest and step back from final review when possible. Sponsorship does not buy roadmap priority. Community behavior follows the [Code of Conduct](https://github.com/YangYuS8/winenv/blob/main/CODE_OF_CONDUCT.md), and vulnerabilities follow the [private security process](https://github.com/YangYuS8/winenv/blob/main/SECURITY.md).
