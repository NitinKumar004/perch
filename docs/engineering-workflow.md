# How we build Perch — the working agreement

Read this before starting any non-trivial work on Perch. It's the rhythm we
follow so the codebase stays something we're proud of: scalable, clean, no
duplication, and wired the way a strong engineering team would wire it.

The short version: **don't just make it work — make it right, then have someone
independent confirm it's right, and keep going until they agree.**

---

## The loop for every feature or fix

1. **Understand first.** Read the code that the change touches — the module
   protocol, the config layer, the render path — before writing anything. Know
   how the existing pieces fit so the new piece matches them.

2. **Build it.** Make the change, following the standards below.

3. **Prove it.** Build succeeds, all tests pass, and the app actually runs. New
   logic gets new tests. Behaviour-preserving refactors keep every test green.

4. **Audit it — independently.** Before we call it done, an independent
   **reviewer agent (Sonnet)** reads the changed code with fresh eyes and judges
   it against the quality bar below. It reports concrete findings, ranked, with
   file:line — not vibes.

5. **Fix everything it finds.** Real findings get fixed in place. If a finding
   is a deliberate non-change, we write down *why* (a one-line rationale), we
   don't silently ignore it.

6. **Re-review.** The reviewer looks again at the fixed code. We repeat 4→6
   **until the reviewer explicitly approves** — i.e. it has no remaining
   scalability, architecture, duplication, or wiring concerns. One clean pass
   from an independent reviewer is the gate, not our own say-so.

7. **Only then** do we move to the next feature, and only then do we ask about
   committing. Nothing is committed or pushed without explicit sign-off.

The point of steps 4–6 is that "it compiles and the tests pass" is the floor,
not the finish line. The finish line is an independent reviewer agreeing the
design is sound.

---

## The quality bar the reviewer checks against

This is what "done right" means here — the same things a strong team would flag
in code review:

- **No duplication.** Every concept lives in exactly one place. If two files do
  the same thing, one of them is wrong. Shared logic becomes a shared helper;
  the copies get deleted, not left behind.

- **One source of truth.** Lists that must agree (modules, settings, catalog)
  derive from a single registry — never parallel hand-maintained lists that can
  drift out of sync.

- **Generic over special-cased.** Prefer a rule that works for every case over a
  switch with a branch per case. The shell shouldn't know one module's name; it
  should read a declared property. Adding the next module/theme/metric should be
  one entry, not edits scattered across the codebase.

- **Dependency injection, done cleanly.** Things a component needs are *handed
  to it* (through its initializer / a context object), never reached for
  globally. No package-level mutable state, no singletons smuggled in. This is
  what keeps modules pure and testable.

- **Clear layering.** Modules are pure producers and never import the UI. The
  shell owns rendering. Config is its own layer. The boundaries hold both
  directions — no UI leaking into a module, no module details leaking into the
  shell.

- **Correct concurrency.** Streams cancel cleanly and tear down fully. No work
  runs on the main actor that would freeze the UI. No data races; shared mutable
  state lives behind an actor. Every timer/task is stored and invalidated.

- **Robust at the edges.** Config writes are atomic; a corrupt or old file
  migrates or resets gracefully, never crashes or silently wipes user data.
  Nil/empty/error inputs are handled.

- **Extensible without breaking.** New capabilities are added as defaulted
  protocol methods, so existing modules keep working untouched.

- **Honest naming and comments.** Names say what a thing is for. Comments say
  *why*, not *what*. Dead code and unused parameters are removed, not left to rot.

---

## Standards in one glance

- Swift 6, strict concurrency. `Sendable` is not optional.
- Table/`@Test` tests with the swift-testing framework; add to existing test
  files where one exists.
- No package-level mutable state — inject it.
- A new module = one entry in the module registry. Nothing else should need to
  change.
- Colours go through the palette (semantic `Tint`), never hardcoded per view.
- Byte sizes/rates, alert-episode tokens, polling loops, threshold→tint — all
  through their shared helper. Don't re-roll them.

---

## Why we work this way

A menu-bar HUD with a plugin-style module system lives or dies on how cheap it
is to add the *next* module, the *next* theme, the *next* metric. Every shortcut
that couples things together taxes every future change. So we pay the cost once,
up front, at the foundation — and we let an independent reviewer hold us to it,
because it's easy to talk yourself into "good enough" on your own work.

Make it work → make it right → have someone independent confirm it's right →
keep going until they agree.
