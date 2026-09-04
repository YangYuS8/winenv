# RFC 0001: Modular core and provider contract

| Field | Value |
| --- | --- |
| Status | Accepted |
| Accepted | 2026-09-04 |
| Scope | Internal architecture; no CLI or profile-format change |

## Summary

Winenv remains an opinionated Windows environment orchestration layer, not a universal package repository or hosted environment-management platform. The stable `win.ps1` entry point loads small internal implementation files, while package-manager-specific behavior is reached through a validated provider registry.

This RFC records the architecture that future changes must preserve. Files under `src/` are internal and may evolve between releases; the `win` command, documented parameters, profile schema, state paths, and release installation flow are the compatibility surface.

## Context

The original single-file implementation made bootstrap and distribution simple, but it grew to more than three thousand lines covering localization, profiles, state, discovery, installers, package managers, and command routing. That made unrelated changes collide and forced contributors to understand most of the program before changing one manager.

Winenv already has a declarative foundation: profiles express desired capabilities, active profiles compose into an effective definition, existing installations can be reused or adopted, and conflicts require an explicit local decision. The next architectural need is to make these responsibilities independently testable without turning Winenv into a general plugin marketplace.

## Decision

### Keep a thin, stable entry point

`win.ps1` owns only:

- command parameters and aliases;
- invocation-scoped paths and state;
- loading internal implementation files;
- localization and provider initialization;
- top-level command dispatch and error localization.

It contains no function implementations. The release archive still exposes the same `win.ps1`, and the installer and launcher continue to invoke it exactly as before.

### Separate responsibilities

| Path | Responsibility |
| --- | --- |
| `src/Localization.ps1` | Language resolution, messages, tables, prompts, and help |
| `src/Core.ps1` | Native execution, command probing, prerequisites, and self-update |
| `src/Profiles.ps1` | Profile parsing, snapshots, composition, conflicts, and selection |
| `src/Inventory.ps1` | Candidates, live search, installed inventory, and adoption |
| `src/Planning.ps1` | Reuse/install planning and installation orchestration |
| `src/State.ps1` | Persistent state and migrations |
| `src/Commands.ps1` | High-level health, update, removal, cleanup, and shell integration |
| `src/Providers/` | Provider contract and manager-specific implementations |

The implementation files are dot-sourced into one invocation scope. This intentionally preserves Windows PowerShell compatibility and the existing test ability to replace individual functions. Internal modules must not execute user actions when loaded.

### Validate providers at startup

Every profile owner must have exactly one registered provider. A provider descriptor contains a stable name and an operation-to-handler map. Startup fails before package work begins when a handler is missing, an unknown operation is registered, or the provider set no longer matches the profile owners.

The first contract covers the operations already safe to normalize:

| Operation | Input | Expected result |
| --- | --- | --- |
| `Search` | Query text | Zero or more normalized package candidates |
| `Install` | Package declaration and invocation context | Install, reuse, or display the explicit vendor handoff |
| `Remove` | Package declaration and invocation context | Delegate removal to the recorded owner |

`winget`, `scoop`, and `mise` implement all three operations. `vendor` implements install and removal handoffs but does not pretend to provide a searchable catalog.

Inventory, inspection, update, adoption, and plan operations remain manager-specific until their inputs and results are genuinely uniform. Adding names to the contract before that point would hide differences instead of containing them.

## Provider admission rules

A new provider is considered only when it solves a machine-level Windows environment responsibility that the existing providers cannot represent. A proposal must document:

1. the concrete user problem and why a profile or existing source cannot solve it;
2. discovery, installation, update, removal, and adoption semantics;
3. privilege, restart, trust, signature, and rollback behavior;
4. interaction with existing installations and ownership;
5. maintenance cost and the behavior when the provider is unavailable;
6. tests for every advertised operation in PowerShell 7 and, where applicable, Windows PowerShell 5.1.

Project dependency ecosystems such as npm, pip, and cargo do not automatically qualify as machine providers. Their runtimes belong in mise, while project dependencies normally remain in the project's own lockfiles. Windows Features or other privileged system capabilities require a separate security design before admission.

The registry is internal in this phase. Third-party code is not loaded from user directories or profiles, and Winenv does not promise a public plugin API.

## Compatibility invariants

Modular changes must preserve:

- the `win` command and documented aliases;
- profile schema version 1 and independent profile snapshots;
- non-destructive profile disable behavior;
- existing software ownership and adoption semantics;
- English-first localization with Simplified Chinese support;
- Windows PowerShell parsing and PowerShell 7 execution;
- the versioned Release ZIP, checksum, installer, and stable launcher;
- explicit confirmation for trust, privilege, and destructive actions.

A change to one of these invariants requires its own RFC, migration plan, and explicit compatibility decision.

## Testing and packaging

CI recursively parses and localization-checks the entry point and every internal PowerShell file. Architecture tests require the entry point to remain function-free, reject duplicate internal function definitions, verify that every implementation file is loaded once, validate every provider handler, and exercise provider dispatch.

The Release builder packages `src/` beside `win.ps1`; the fresh-system installation smoke test verifies the provider contract is present in the installed version. Internal files therefore participate in the same checksummed, versioned update boundary as the entry point.

## Non-goals

This decision does not create:

- a public plugin marketplace or compatibility promise for internal functions;
- a Winenv-maintained universal package index;
- an account service, enterprise control plane, role-based access system, or web dashboard;
- automatic management of every npm, pip, cargo, Docker, WSL, or Windows feature;
- strict removal of software not declared by a profile.

Team use should continue to start with reviewable profiles stored in Git. Enterprise-only mechanisms will be considered only after concrete users demonstrate requirements that file-based distribution cannot meet.

## Next steps

The modular split and initial provider registry are complete under this RFC. Future work should proceed in this order:

1. expose a read-only `win diff` using the existing effective-profile and inventory models;
2. evaluate an optional lockfile that records resolved versions, sources, and hashes without replacing profile intent;
3. design `win sync` so install and repair are safe by default and removal requires an explicit prune option;
4. normalize more provider operations only after their behavior can be expressed honestly across managers;
5. consider a public extension surface only after the internal contract has remained stable across multiple releases.

## Consequences

The architecture adds multiple files to the Release and makes direct raw-file execution of only `win.ps1` insufficient; the supported installer already downloads the complete checksummed archive. In return, changes become smaller, provider responsibilities become visible, tests can enforce boundaries, and future declarative features can reuse a stable core without committing Winenv to becoming a platform.
