// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if canImport(AppIntents)
import AppIntents
import Foundation

/// User-facing App Intent for the `system.snapshot` bridge capability.
///
/// Read-only: returns a short human summary of CPU / memory / disk / network
/// and embeds the full metrics in the bridge receipt. Nothing leaves the Mac.
@available(macOS 14.0, *)
struct SystemSnapshotIntent: AppIntent {
    static var title: LocalizedStringResource = "System Snapshot"
    static var description = IntentDescription(
        "Read a point-in-time CPU, memory, disk, and network summary. Local only — nothing is uploaded.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let input = SystemSnapshotBridge.Input(
            caller: BridgeCaller(
                id: Bundle.main.bundleIdentifier ?? "io.elevenviews.tools",
                name: AppInfo.name,
                teamId: nil,
                signingIdentifier: Bundle.main.bundleIdentifier))

        let receipt = await SystemSnapshotBridge.perform(input)
        guard receipt.outcome == .success,
              let metrics = receipt.artifacts?.first?.inline else {
            throw SystemSnapshotIntentError(receipt: receipt)
        }

        let summary = String(
            format: "CPU %.1f%% · Memory %@ / %@ · Disk free %@ · Net ↓ %@/s ↑ %@/s",
            metrics.cpuLoadPercent,
            byteString(metrics.memoryUsedBytes),
            byteString(metrics.memoryTotalBytes),
            byteString(metrics.diskFreeBytes),
            byteString(UInt64(metrics.networkDownBytesPerSec.rounded())),
            byteString(UInt64(metrics.networkUpBytesPerSec.rounded())))

        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }

    private func byteString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}

@available(macOS 14.0, *)
struct SystemSnapshotIntentError: Error, CustomLocalizedStringResourceConvertible {
    let receipt: BridgeReceipt

    var localizedStringResource: LocalizedStringResource {
        let reason = receipt.error?.message ?? "System snapshot failed (\(receipt.outcome.rawValue))."
        return "\(reason)"
    }
}
#endif
