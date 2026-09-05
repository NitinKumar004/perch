# Perch

[![CI](https://github.com/NitinKumar004/perch/actions/workflows/ci.yml/badge.svg)](https://github.com/NitinKumar004/perch/actions/workflows/ci.yml)

A modular, accuracy-first developer HUD for the MacBook notch. Glance up to know
your build, PRs and deploys are fine — instead of tab-switching to find out.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/NitinKumar004/perch/main/get.sh | bash
```

Downloads the latest `Perch.app`, drops it in `/Applications`, and launches it.
No Apple ID, no password. The app is **unsigned** (ad-hoc signed) — installing
via `curl` avoids the Gatekeeper prompt because the download isn't quarantined.
(If you download the zip in a browser instead, right-click the app → **Open**
the first time.)

## Requirements

- macOS 14+
- To build from source: Swift 6.1+ (Xcode 16 toolchain)

## Run from source

```bash
swift run Perch
```

Perch launches as a background agent — no Dock icon, just a 🐦 menu-bar item and
the notch HUD. Click a pill to connect GitHub (device flow) or open the detail
panel; use **Settings…** to configure everything.

## Test

```bash
swift test
```

## Modules

Each signal is a module. Place any of them in the left pill, right pill, or the
drop-down panel.

| Module | id | Shows | Needs |
|---|---|---|---|
| Build | `github.builds` | latest Actions run: passing / failing / running | GitHub |
| Pull requests | `github.prs` | count of PRs waiting on your review | GitHub |
| Deploy health | `deploy.health` | ping a URL: up / degraded / down | a URL |
| CPU | `system.cpu` | system CPU %, green/amber/red | — (local) |
| Focus timer | `focus.timer` | a local countdown / pomodoro | — (local) |
| Clock | `system.clock` | the time | — (local) |

## Configure

Two ways, same result:

- **Settings…** (🐦 menu) — a native window: pick a module per slot and fill its
  settings. Save re-wires the notch immediately.
- **Edit Configuration File…** — `~/.config/perch/layout.json`, then **Reload
  Configuration**. The file is versioned; a corrupt file is backed up and reset
  so the app always starts.

Example `layout.json`:

```json
{
  "schemaVersion": 1,
  "activePreset": "default",
  "presets": {
    "default": {
      "leftPill":  { "module": "github.builds", "settings": { "repo": "you/app", "branch": "main" } },
      "rightPill": { "module": "github.prs",    "settings": { "queue": "review-requested" } },
      "panel":     [ { "module": "github.builds" }, { "module": "system.cpu" } ]
    }
  }
}
```

## Architecture

Dependencies point one way. A module can never import the UI; the UI can never
import a provider. See `docs/architecture.md`.

```
PerchCore        domain vocabulary — Slot, Freshness, Snapshot, Tint (no deps)
PerchModuleKit   the SDK: NotchModule protocol, PillFace/PillContent, registry
PerchSync        the accuracy engine: VersionedStore (ordering + freshness)
PerchGitHub      device-flow auth + Keychain + API client
PerchConfig      the versioned layout.json (sources, slots, settings, presets)
PerchModules     the modules: Build, PRs, Deploy, CPU, Timer, Clock + catalog
PerchNotchUI     the notch window (AppKit) + SwiftUI pills + drop-down panel
PerchApp         composition root: config → modules → slots → window + settings
```

### The two ideas that make it clean

1. **Modules are pure.** A `NotchModule` produces a typed `Snapshot<State>`
   stream and a pure `face(for:)` mapping to a declarative `PillFace`. It never
   touches SwiftUI and never knows where it's rendered. Adding a signal = one
   new module, nothing else changes.

2. **The HUD never lies.** Every value carries a `Freshness`
   (`live` / `computing` / `stale(since:)` / `unknown` / `error`). The
   `VersionedStore` accepts a new value only if it is *strictly newer*, so
   out-of-order or duplicate events can never move state backwards, and a value
   past its TTL is shown dimmed as stale — never as a confident, wrong "green".

## Privacy

Everything is local. The GitHub token lives in the macOS Keychain (device-only);
build/PR status is held in memory only. No server, no database, nothing leaves
your Mac except the calls to GitHub itself.

## Status

Working: GitHub build + PR modules, deploy/CPU/timer/clock, the config engine,
the settings window, and the drop-down panel. Remaining: notarization + Sparkle
auto-update (so it installs without building), and a non-notch floating fallback.
See `docs/roadmap.md`.
