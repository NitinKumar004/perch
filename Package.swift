// swift-tools-version: 6.0
import PackageDescription

// Perch — a modular, accuracy-first developer HUD for the MacBook notch.
//
// The package is split into small single-responsibility modules whose
// dependencies point one way only:
//
//   PerchCore  ← PerchModuleKit ← PerchModules ─┐
//        ↑            ↑                          ├→ PerchApp (executable)
//   PerchSync ────────┘        PerchNotchUI ─────┘
//
// A module can never import a layer "above" it, so the notch UI literally
// cannot reach a provider and a provider can never draw a pixel.
let package = Package(
    name: "Perch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Perch", targets: ["PerchApp"]),
        .library(name: "PerchModuleKit", targets: ["PerchModuleKit"]),
    ],
    targets: [
        // Pure domain vocabulary. No dependencies, no UI.
        .target(name: "PerchCore"),

        // The public SDK surface every module is written against.
        .target(name: "PerchModuleKit", dependencies: ["PerchCore"]),

        // The accuracy engine: versioned last-write-wins + freshness.
        .target(name: "PerchSync", dependencies: ["PerchCore"]),

        // GitHub integration: device-flow auth + Keychain token storage.
        // (API queries + modules land on top of this.)
        .target(name: "PerchGitHub", dependencies: ["PerchCore"]),

        // User-facing configuration: the versioned layout.json — sources,
        // slot assignments, per-module settings, presets. Loading + migration.
        .target(name: "PerchConfig", dependencies: ["PerchCore"]),

        // First-party modules (local Clock, a demo Build, and the real GitHub build).
        .target(name: "PerchModules", dependencies: ["PerchModuleKit", "PerchSync", "PerchGitHub", "PerchConfig"]),

        // The notch window + SwiftUI rendering of the declarative pill vocabulary.
        .target(name: "PerchNotchUI", dependencies: ["PerchModuleKit"]),

        // Composition root: wires modules → slots → window. The only place
        // that knows about every layer at once.
        .executableTarget(
            name: "PerchApp",
            dependencies: ["PerchCore", "PerchModuleKit", "PerchSync", "PerchModules", "PerchNotchUI"]
        ),

        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchSyncTests", dependencies: ["PerchSync", "PerchCore"]),
        .testTarget(name: "PerchGitHubTests", dependencies: ["PerchGitHub", "PerchCore"]),
        .testTarget(name: "PerchConfigTests", dependencies: ["PerchConfig", "PerchCore"]),
    ]
)
