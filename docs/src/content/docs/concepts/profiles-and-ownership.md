---
title: Profiles, claims, and ownership
description: Understand why declaring software, installing it, and disabling a Profile are three separate operations.
sidebar:
  order: 1
---

A Profile describes a desired environment. It is not a second copy of a package manager's database, and it is not an uninstall list.

## Three separate questions

| Question | Answer comes from |
| --- | --- |
| What should this environment contain? | Active Profile declarations |
| What is actually installed? | Manager inventory and Windows installation records |
| Who can update or remove this installation? | The manager or original vendor installation route |

`win diff` compares the first two. It does not infer ownership from a familiar application name, and it does not remove extra software simply because no Profile mentions it.

## Shared Profiles add independent claims

Importing someone else's Profile saves an independent snapshot. It does not overwrite your personal layer. Two matching declarations retain both references while requesting one installation. Incompatible versions or competing command providers need an explicit local decision.

Disabling a shared Profile removes its active claims. Software referenced by another layer remains referenced. Software with no remaining claim becomes `unclaimed`, but stays installed and managed through its original route. Removal remains a separate, explicit action.

## Reuse is different from adoption

Reuse means an existing compatible installation satisfies a requirement. Adoption means recording a reproducible declaration for selected existing software. Neither requires pretending Winenv installed the software originally.

Unknown EXE/MSI installations may remain visible only as Windows records. Winenv does not invent a package identity or promise it can reproduce them.

See [Composing profiles](/winenv/guide/profiles/) for operations, [existing-PC adoption](/winenv/guide/existing-windows/) for onboarding, and [state and security](/winenv/reference/state-and-security/) for storage details.
