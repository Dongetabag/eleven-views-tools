// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import PackageDescription

let package = Package(
    name: "ElevenViewsTools",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Vorssaint",
            path: "Sources/Vorssaint"
        ),
        // The versioned local bridge contract + signed XPC transport (ELE-3160).
        // Transport-independent code (contract, registry, trusted-caller policy,
        // authorizer) has no Apple-only dependency; the signature verifier and
        // XPC listener are gated behind canImport(Security)/canImport(XPC).
        .target(
            name: "ElevenViewsBridgeIPC",
            path: "Sources/ElevenViewsBridgeIPC"
        ),
        // On-Mac proof: connects to the signed listener and prints the receipt.
        .executableTarget(
            name: "bridge-harness",
            dependencies: ["ElevenViewsBridgeIPC"],
            path: "Sources/BridgeHarness"
        ),
        .testTarget(
            name: "ElevenViewsBridgeIPCTests",
            dependencies: ["ElevenViewsBridgeIPC"],
            path: "Tests/ElevenViewsBridgeIPCTests"
        )
    ]
)
