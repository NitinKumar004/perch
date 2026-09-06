# Roadmap

Where Perch is going. The north star: a calm, trustworthy "is everything okay?"
in the notch — fully customizable, accuracy-first, and local.

## Done

- **Walking skeleton** — notch window, module/slot architecture, accuracy engine.
- **GitHub auth** — device flow + Keychain, plus Personal Access Token and `gh`
  CLI sign-in for private repos.
- **Config engine** — versioned `layout.json`: any number of sources, per-slot
  and per-module settings, presets, safe loading (validate, drop unknowns, back
  up + reset corrupt, migrate forward), and **hot-reload** on external edits.
- **Settings window** — native UI; per-module settings rendered automatically
  from the catalog (text / dropdown / toggle). Launch-at-login, auto-open-on-red,
  quiet hours, HUD position.
- **Modules** —
  1. **Pull requests** — review verdict, mergeable, and **CI progress ("5/10")**.
  2. **Builds** — one repo, and **multi-repo** (worst-of + per-repo list).
  3. **Deploy health** — ping any URL; healthy / degraded / down.
  4. **Timer / pomodoro** — local, pause/reset controls.
  5. **System vitals** — CPU, RAM, and **network throughput**.
  6. **Clipboard history** — on-device; click a past copy to reuse it.
  7. **Dev-server monitor** — is a local port (`:3000`) listening?
  8. **Clock / Battery** — local, configurable (12/24h, seconds).
- **Notifications** — native alerts on red build / new review, with quiet hours.
- **Panel** — per-module detail: workflow, commit, duration, open-run link, the
  PR list, deploy breakdown, sparklines and progress bars.
- **Ship basics** — non-notch fallback (flank / right / below), first-launch
  onboarding, and an update check against GitHub Releases (prompts the one-line
  reinstall — the honest fit for unsigned `curl | bash` distribution).

## Still open

- **File shelf** — the drag-and-drop half of "clipboard + file shelf". Needs a
  drop target in the panel (a new interaction surface), so it's its own task.
- **Next-meeting countdown** — a Calendar module. Needs EventKit permission +
  entitlements, which touch the unsigned-distribution story; scoped separately.
- **Sparkle auto-update** — true in-app auto-update needs code-signing + an
  appcast. Deferred deliberately; the release-based update check covers the gap.

## Principles that never bend

- **Accuracy first** — never a confident, wrong value; show stale/unknown honestly.
- **Local only** — no server, no database; token in Keychain, status in memory.
- **Decoupled** — a module produces typed state; the shell renders it. Adding a
  feature never touches the other layers.
