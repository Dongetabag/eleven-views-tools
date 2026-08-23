// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// One-shot, permission-free reader that fills a `SystemSnapshotPayload` from
/// the same primitives the live `SystemMonitor` samples. It is deliberately
/// independent of the monitor's UI-driven lifecycle: a bridge caller can ask
/// for a snapshot without any panel being open, and nothing here needs a macOS
/// grant (`system.snapshot` declares no permissions in the registry).
///
/// CPU load and network throughput are rates, so they need two reads a short
/// interval apart; memory and disk are instantaneous point-in-time facts.
enum SystemSnapshotReader {
    /// How long to wait between the two counter reads used to derive the CPU
    /// and network rates. Short enough to feel instant, long enough to produce
    /// a stable rate.
    static let sampleInterval: Duration = .milliseconds(250)

    static func read() async -> SystemSnapshotPayload {
        let cpuStart = readCPUTicks()
        let networkSampler = NetworkSampler()
        _ = networkSampler.sample(now: ProcessInfo.processInfo.systemUptime)

        try? await Task.sleep(for: sampleInterval)

        let cpuEnd = readCPUTicks()
        let network = networkSampler.sample(now: ProcessInfo.processInfo.systemUptime)

        let cpuFraction = cpuLoadFraction(from: cpuStart, to: cpuEnd) ?? 0
        let memory = SystemInfo.memoryUsage()
        let disk = rootVolumeCapacity()

        return SystemSnapshotPayload(
            cpuLoadPercent: SystemSnapshotPayload.cpuLoadPercent(fromFraction: cpuFraction),
            memoryUsedBytes: memory?.used ?? 0,
            memoryTotalBytes: memory?.total ?? ProcessInfo.processInfo.physicalMemory,
            diskFreeBytes: disk.free,
            diskTotalBytes: disk.total,
            networkUpBytesPerSec: nonNegativeBytes(network.upBytesPerSec),
            networkDownBytesPerSec: nonNegativeBytes(network.downBytesPerSec)
        )
    }

    // MARK: - CPU

    private struct CPUTicks {
        var busy: UInt64
        var total: UInt64
    }

    /// Aggregated busy/total ticks from `HOST_CPU_LOAD_INFO`, the same source
    /// `SystemMonitor.readCPUUsage()` uses.
    private static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        return CPUTicks(busy: busy, total: busy + idle)
    }

    private static func cpuLoadFraction(from start: CPUTicks?, to end: CPUTicks?) -> Double? {
        guard let start, let end, end.total > start.total else { return nil }
        return Double(end.busy - start.busy) / Double(end.total - start.total)
    }

    // MARK: - Disk

    /// Total / available capacity of the boot volume. Uses the Foundation
    /// volume keys (no Full Disk Access needed) and falls back to `statvfs`
    /// if the resource values are unavailable.
    private static func rootVolumeCapacity() -> (total: UInt64, free: UInt64) {
        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) {
            let total = values.volumeTotalCapacity.map { UInt64(max(0, $0)) } ?? 0
            let free = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) } ?? 0
            if total > 0 { return (total, free) }
        }

        var stats = statvfs()
        guard statvfs("/", &stats) == 0, stats.f_frsize > 0 else { return (0, 0) }
        let frsize = UInt64(stats.f_frsize)
        return (UInt64(stats.f_blocks) * frsize, UInt64(stats.f_bavail) * frsize)
    }

    // MARK: - Helpers

    private static func nonNegativeBytes(_ value: Double?) -> UInt64 {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return UInt64(value.rounded())
    }
}

/// Runs the `system.snapshot` capability end to end: read the snapshot, wrap it
/// in a v1 receipt (or a `failed` receipt if the read blows up), and hand back
/// the receipt for the App Intent / IPC layer to serialize.
enum SystemSnapshotBridge {
    static func run(requestId: UUID = UUID()) async -> BridgeReceipt {
        let startedAt = Date()
        let payload = await SystemSnapshotReader.read()
        let completedAt = Date()

        let artifact = BridgeArtifact(
            kind: .json,
            mimeType: "application/json",
            inline: payload,
            description: "Point-in-time system snapshot from the local SystemMonitor services."
        )

        return BridgeReceipt(
            requestId: requestId,
            capability: Bridge.Capability.systemSnapshot,
            outcome: .success,
            artifacts: [artifact],
            permissionsUsed: [],
            startedAt: startedAt,
            completedAt: completedAt
        )
    }
}
