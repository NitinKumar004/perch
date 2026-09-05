# Roadmap

Where Perch is going. The north star: a calm, trustworthy "is everything okay?"
in the notch — fully customizable, accuracy-first, and local.

## Done

- **Walking skeleton** — notch window, module/slot architecture, accuracy engine.
- **GitHub auth** — device flow + Keychain token storage.
- **Live build signal** — the CI pill tracks a repo's GitHub Actions runs.

## Now: make it fully customizable

The user should control *what* they watch, *where* it shows, and *what* each
module displays — with no code editing.

### A · Config engine
A versioned `~/.config/perch/layout.json`:
- **Sources** — any number of repos (`owner/name` + branch), not just one.
- **Slots** — assign a module to `leftPill`, `rightPill`, or `panel`.
- **Per-module settings** — each module declares its own settings; they live here.
- **Presets** — named layouts you switch in one click.
- Safe loading: validate against the module registry, drop unknowns with a
  warning, back up + reset a corrupt file, migrate old versions forward.
- Hot-reload when the file changes.

### B · Settings window
A native preferences UI so no one has to touch JSON:
- Add/remove repos, drag modules to slots, toggle modules.
- Per-module settings rendered automatically from what the module declares.
- Presets, poll interval, auto-open-on-red, launch-at-login, quiet hours.

## Then: the modules (features)

Each is one plug-in behind the same `NotchModule` contract, so every one is
automatically customizable once the config engine exists.

1. **Pull requests** — mine vs waiting-on-me, review verdict, mergeable.
2. **Multi-repo builds** — watch several repos at once.
3. **Deploy health** — ping any URL(s); healthy / degraded / down.
4. **Timer / pomodoro** — local, optionally labelled from the git branch.
5. **System vitals** — CPU / RAM / network.
6. **Clipboard + file shelf** — on-device only.
7. **Notifications** — native alert on a red build or a review request.

## Then: the panel

Click the notch → a detail report per module: workflow name, duration, commit,
"open run" link, the failing job on red; the PR list; the deploy breakdown.

## Then: ship

- Non-notch Mac fallback (floating pill under the menu bar).
- Notarize + Sparkle auto-update, so anyone installs without building.
- First-launch onboarding.

## Principles that never bend

- **Accuracy first** — never a confident, wrong value; show stale/unknown honestly.
- **Local only** — no server, no database; token in Keychain, status in memory.
- **Decoupled** — a module produces typed state; the shell renders it. Adding a
  feature never touches the other layers.
