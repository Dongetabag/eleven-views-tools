// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppIntents
import Foundation

/// The first `ElevenViewsBridge` capability exposed as an App Intent:
/// `system.snapshot`. It is read-only, needs no macOS permission and nothing
/// leaves the Mac — it returns a v1 bridge receipt whose single inline JSON
/// artifact is the CPU / memory / disk / network summary read from the local
/// SystemMonitor services.
///
/// The intent is the direct (Shortcuts / same-process) entry point. The signed
/// cross-process IPC layer that verifies a `caller` and enforces approval
/// tokens is a separate concern (ELE-3160); this capability requires neither,
/// so it is safe to expose on its own.
struct SystemSnapshotIntent: AppIntent {
    static var title: LocalizedStringResource = "System Snapshot"

    static var description = IntentDescription(
        "Read-only CPU, memory, disk and network summary from the local system monitor. Nothing leaves the Mac.",
        categoryName: "System"
    )

    /// A read that reports current state must never launch or foreground the app.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let receipt = await SystemSnapshotBridge.run()
        let json = try receipt.jsonString()
        return .result(value: json, dialog: IntentDialog(stringLiteral: receipt.summaryLine))
    }
}

/// Surfaces the snapshot intent in the Shortcuts app and Spotlight with a few
/// natural-language phrases.
struct BridgeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SystemSnapshotIntent(),
            phrases: [
                "Get a \(.applicationName) system snapshot",
                "\(.applicationName) system snapshot"
            ],
            shortTitle: "System Snapshot",
            systemImageName: "gauge.with.dots.needle.bottom.50percent"
        )
    }
}
