---
layout: home

hero:
  name: Winenv
  text: Make Windows software manageable
  tagline: One compact interface for WinGet, Scoop, and mise. Search live catalogs, compose profiles, and bring an existing PC under control without starting over.
  image:
    src: /logo.svg
    alt: Winenv
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: Command reference
      link: /reference/commands

features:
  - icon: 🔎
    title: Search real catalogs
    details: Query WinGet, Scoop, and mise at runtime. Every matching source stays visible, with no hand-maintained package index to become stale.
  - icon: 🧩
    title: Compose profiles
    details: Runtime requirements, personal baselines, and community profiles remain independent. Identical claims merge; real conflicts ask for a decision.
  - icon: ♻️
    title: Respect the current PC
    details: Scan software already installed, adopt only reproducible entries, and leave unknown local applications untouched. Reinstallation is never a prerequisite.
  - icon: ⚡
    title: Keep daily commands short
    details: Use win, win up, win rm, and win check for common work. Long action names remain available for existing automation.
  - icon: 🛡️
    title: Make trust boundaries visible
    details: Third-party sources, raw installers, and local manifests show their origin and verification data before anything runs.
  - icon: 🚀
    title: Automate the maintenance work
    details: Commit history produces versions, release notes, verified assets, and this documentation site through GitHub Actions.
---

## Three managers, one clear policy

Winenv borrows Omarchy's idea of assigning each tool a clear responsibility without copying a Linux software stack onto Windows:

| Need | Default manager | Typical software |
| --- | --- | --- |
| Installer, service, file association, or Windows integration | WinGet | Browsers, editors, desktop apps |
| Portable, user-scoped command-line tool | Scoop | Small CLIs and single-file tools |
| Development runtime that must switch versions between projects | mise | Node.js, Go, Python |

This is a decision order, not a hard-coded catalog. The final choice comes from the catalogs available on your machine and your confirmation.

```powershell
# Open the terminal software picker
win

# Start with a query or constrain the manager
win vscode
win node -From mise
```

[Learn how search and package ownership work →](/guide/packages)
