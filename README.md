# Perch

A modular, accuracy-first developer HUD for the MacBook notch. Glance up to know
your build, PRs and deploys are fine — instead of tab-switching to find out.

> This repo is the **walking skeleton**: the notch window, the module/slot
> architecture, the accuracy engine, and one local module (Clock) plus a
> simulated Build signal that exercises the whole pipeline. Real integrations
> (GitHub, deploys, vitals) slot in behind the same contract.

## Requirements

- macOS 14+
- Swift 6.1+ (Xcode 16 toolchain)

## Run

```bash
swift run Perch
```

Perch launches as a background agent — no Dock icon. Look at your notch: a **CI**
pill on the left (cycling running → passing → failing to show state changes and
the accuracy engine rejecting an out-of-order event) and a **clock** on the
right. Quit from the 🐦 menu-bar item.

## Test

```bash
swift test
```

## Architecture

Dependencies point one way. A module can never import the UI; the UI can never
import a provider.

```
PerchCore        domain vocabulary — Slot, Freshness, Snapshot, Tint (no deps)
PerchModuleKit   the SDK: NotchModule protocol, PillFace/PillContent, registry
PerchSync        the accuracy engine: VersionedStore (ordering + freshness)
PerchModules     concrete modules: Clock, FakeBuild
PerchNotchUI     the notch window (AppKit) + SwiftUI pill rendering
PerchApp         composition root: wires modules → slots → window
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

## Status

Walking skeleton — see the architecture plan for the full roadmap
(real GitHub provider, config/presets, plugin SDK, notarization + Sparkle).
