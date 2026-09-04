# Agent instructions for Winenv

[简体中文](./AGENTS.zh-CN.md)

These are the repository-wide working rules for coding agents. English is canonical; the Chinese companion is a translation, not a separate override. Respect higher-priority instructions and the current task's permissions. Use the requester's language when discussing work.

## Review the decision before implementing it

Act as a critical engineering partner, not a rubber stamp. Understand the user's underlying problem and compare the requested solution with the accepted scope, architecture, and actual code. Apply this review to your own proposals too.

Before making changes, raise a material concern if the request or proposed implementation:

- depends on a false premise, contains a logical contradiction, or cannot deliver its stated outcome;
- materially differs from the previously agreed requirement, acceptance criteria, or a documented project decision;
- changes software ownership, profile composition, compatibility, trust, privileges, or destructive behavior without addressing the consequences;
- introduces disproportionate complexity or ongoing maintenance for a small, maintainer-led project when a simpler approach meets the same need.

Do not call a preference or an unverified hunch a fundamental error. Inspect relevant code and tests; verify uncertain upstream behavior in primary documentation. Separate facts, assumptions, and tradeoffs. A changed requirement can be intentional: surface the change rather than assuming the earlier decision must win forever.

### When there is a material concern

1. Pause implementation of the disputed part before editing files, installing tools for that approach, or changing external state. Safe, relevant read-only investigation may continue.
2. Explain the original goal, the proposed change, the specific conflict, and the likely consequences. Cite concrete code, tests, an accepted decision, or authoritative evidence. State uncertainty honestly.
3. Recommend the best-supported option under the user's constraints. Explain why it is preferable and what it costs; do not present personal taste as a universally optimal solution. Offer a smaller experiment when evidence is incomplete.
4. Ask the user to choose before proceeding with the disputed work. Do not implement your preferred alternative without approval, and do not treat a warning delivered alongside implementation as consent.
5. If the user accepts the recommendation, implement it. If, after hearing the reasons and risks, the user explicitly insists on the original direction, honor that informed decision within higher-priority safety rules, permissions, and technical feasibility.
6. Record the chosen direction and accepted tradeoffs briefly in the conversation; update the relevant issue/RFC and migration notes when required by project policy and authorized. Resume work without repeatedly reopening the same argument or silently reverting to your preference. Revisit only if material new evidence or scope changes arise.

An initial request, silence, or approval given before a concern was disclosed is not an informed override. A short reply such as “同意” is sufficient when it unambiguously accepts the immediately preceding recommendation; clarify only when the chosen direction is genuinely ambiguous. Approval applies to that decision, not to unrelated actions or removal of this review rule. Do not promise an impossible result or bypass a security restriction because the user insists; explain the remaining constraint and offer a feasible path.

### Keep the review proportional

Proceed with ordinary, in-scope fixes and low-risk implementation details without asking for approval at every step. This rule is not a veto over the user's goals and must not create approval loops for naming, formatting, or equally reasonable implementations.

Examples for this project:

| Request | Expected response |
| --- | --- |
| Fix malformed Markdown and add a rendering regression test | Proceed; the intended behavior and scope are clear. |
| Make `win off` uninstall software no longer claimed by a profile | Pause: disabling declarations currently preserves installed software; recommend separate, explicit removal. |
| Maintain a hand-curated index to hide duplicate WinGet/Scoop search results | Explain the maintenance and identity risks; recommend live catalogs with visible source-qualified choices. |
| Require WSL or a fresh Windows installation to use Winenv | Flag the conflict with native Windows and existing-PC onboarding before redesigning anything. |
| The user accepts the explanation and explicitly confirms a changed contract | Record the new decision and necessary migration/tests, then implement the approved scope. |

## Preserve Winenv's product boundaries

- Winenv is a native Windows 11 orchestration layer inspired by Omarchy's division of responsibilities, not an Omarchy clone or a fourth package repository. Keep routine `win` commands short and preserve documented aliases.
- WinGet handles Windows-integrated applications, Scoop portable tools, and mise versioned development runtimes. Search live catalogs, show sources, and do not silently equate similarly named packages. Vendor installations remain explicit handoffs, not invented searchable packages.
- Keep `profile.json` limited to Winenv runtime requirements. Do not add personal software, profiles, machine paths, or credentials. Node.js and pnpm used for this repository's documentation are not Winenv runtime prerequisites.
- User and shared profiles are independent snapshots. Identical claims can merge; real version/provider conflicts require a decision. Disabling a profile does not uninstall software. Reuse, adoption, desired declarations, installed inventory, and actual ownership are distinct concepts.
- Support existing PCs without resetting them. Respect each manager's pins, holds, and declared versions. Keep cleanup scoped to unused versions; do not remove versions required by active configurations.
- Keep source, HTTPS, hash, signature, privilege, and destructive-action decisions explicit. Never silently disable Windows protections, elevate, replace a trusted source, or guess arbitrary EXE/MSI installation arguments. Product-design approval is not permission to modify the maintainer's actual installed software.

Changes to these boundaries require the decision review above and the compatibility/security work described in the existing project policies; they are not routine refactors.

## Work from the actual repository

Check `git status` before editing and preserve unrelated work. Read only the relevant source, tests, and documentation for the task. Current files and verified upstream facts take precedence over stale recollections.

- [README.md](./README.md) and [CONTRIBUTING.md](./CONTRIBUTING.md): purpose, contribution workflow, and supported commands.
- [RFC 0001](./docs/src/content/docs/reference/architecture.md): module responsibilities, provider admission, and compatibility contracts. `win.ps1` is a thin entry point with no function implementations; put behavior in the appropriate `src/` module. Loading modules must not perform user actions. `src/Providers/` is an internal validated registry, not a public plugin API.
- [SECURITY.md](./SECURITY.md), [GOVERNANCE.md](./GOVERNANCE.md), and [state/security reference](./docs/src/content/docs/reference/state-and-security.md): trust boundaries, decision authority, and persistent state. Discuss material contract changes before coding; do not silently rewrite these documents to make a conflicting request appear compliant.
- [Documentation maintenance](./docs/src/content/docs/community/documentation.md): Astro Starlight, source ownership, bilingual content, links, and deployment rules.

Prefer a small, complete change over speculative frameworks, new providers, or dependencies. Reuse existing modules, tests, and automation. Do not introduce a second toolchain or weaken a check just to obtain a green build.

## Verify the requested behavior

For a bug, reproduce it and add a regression test that fails before the fix where practical. Verify rendered behavior when fixing Markdown or UI; a successful build alone does not prove formatting, navigation, or localization is correct.

Use the Node.js version in `.node-version` (or a compatible newer version, as permitted by `CONTRIBUTING.md`) and pnpm pinned by `package.json`; `pnpm-lock.yaml` is the dependency lockfile. Follow [development setup](./CONTRIBUTING.md#development-setup) if tools are missing; do not silently change global tool versions.

For documentation and repository-policy changes:

```sh
pnpm install --frozen-lockfile
pnpm test:docs
pnpm docs:build
```

For rendered content, navigation, styling, or language behavior, also run:

```sh
pnpm exec playwright install chromium
pnpm docs:test
```

For PowerShell behavior, run the relevant regression tests and the full supported Windows checks:

```powershell
pwsh -NoProfile -File ./scripts/test.ps1
powershell.exe -NoProfile -File ./scripts/test-windows-powershell.ps1
```

Linux PowerShell mocks do not establish Windows integration or Windows PowerShell 5.1 compatibility. Report unavailable checks honestly and use the authorized Windows CI workflow. Use harmless fixtures and isolated test state instead of installing/removing real user software to test a route.

English is the source language; update affected Simplified Chinese CLI strings, documentation, and policy translations in the same change. Translation-only corrections need not touch unchanged English. Preserve published routes and anchors. Root policies and `CHANGELOG.md` remain canonical; do not edit generated documentation wrappers or erase compatibility records to pass checks.

## Keep delivery and authority explicit

- A request to inspect, research, evaluate, or diagnose authorizes investigation, not implementation or publication. For approved changes, complete the implementation and proportionate checks within the requested scope. Ask before materially expanding it.
- Commit, push, open issues/PRs, or modify repository settings only within the currently authorized workflow. Do not infer blanket permission from a past approval. Never discard unrelated changes or rewrite shared history to simplify a task.
- Use Conventional Commits. Documentation-only changes normally use `docs:`; do not use `fix:` merely to force a software release. Do not manually edit `VERSION` or release history, create release tags/assets, or upload site output. Existing GitHub Actions own releases and Pages, including the exact validated source revision.
- When publication is authorized, verify the relevant workflow result and live behavior before calling it deployed. If blocked, state what is complete and what remains. A green workflow is not a claim that every runtime or UI scenario was tested.
- Keep updates concise. The handoff should name the outcome, relevant files or links, actual validation, unresolved risks, and any informed decision that changed the original scope.

## Maintain these instructions

Keep this file focused on durable project decisions, not task logs or personal configuration. Update `AGENTS.md` and `AGENTS.zh-CN.md` together; the existing policy-pair check enforces paired changes, not semantic translation accuracy. This file guides agents but does not replace tests, security controls, or maintainer review.
