# Governance

[简体中文](./GOVERNANCE.zh-CN.md)

Winenv is currently a maintainer-led project. Governance is intentionally lightweight so a small project can make decisions without hiding how those decisions are made.

## Roles

- **Users** install Winenv, ask questions, and report problems.
- **Contributors** submit documentation, translations, tests, code, or design proposals.
- **Reviewers** are trusted contributors who may triage and review in areas where they have demonstrated context.
- **Maintainers** merge changes, manage releases and repository settings, enforce community policy, and make final project decisions.

The current lead maintainer is [YangYuS8](https://github.com/YangYuS8). There is no paid support team or foundation behind the project.

## Decision process

Routine fixes and documentation changes are decided through pull-request review. Material changes to package ownership, profile semantics, security boundaries, compatibility, or automation should begin with an issue that records the user problem, alternatives, migration impact, and decision.

The maintainer aims for rough consensus and may request more evidence or a narrower experiment. When consensus is not possible, the maintainer decides based on project scope, security, maintenance cost, backward compatibility, and benefit to users. The reason should be recorded publicly unless privacy or security prevents it.

## Becoming a reviewer or maintainer

Roles are earned through sustained, constructive contributions and sound judgment. A maintainer may invite a contributor to review a documented area. Maintainer access additionally requires a history of secure repository practices and reliable collaboration.

Permissions follow least privilege and may be removed after prolonged inactivity, a security concern, or a Code of Conduct violation. A future group of active maintainers should replace unilateral appointment with a recorded majority decision.

## Releases and assets

Only repository automation publishes official versions, tags, checksums, or Pages deployments. Maintainers approve changes but do not hand-build release artifacts. The latest stable release is the supported channel.

## Conflicts of interest

Anyone with a personal, employment, or financial interest that could reasonably affect a decision should disclose it and step back from final review when another qualified reviewer is available. Sponsorship does not purchase roadmap priority or technical approval.

## Changing governance

Governance changes use a pull request that updates both English and Chinese versions. The lead maintainer approves the current model; if the project gains multiple maintainers, approval should come from a majority of active maintainers after a public comment period.
