import AppKit

// Perch runs as a background agent — no Dock icon, no app menu — so it lives in
// the notch and the menu bar only. `.accessory` is the runtime equivalent of
// the LSUIElement Info.plist flag and needs no app bundle, which keeps the
// zero-setup, unsigned-friendly distribution story intact.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
