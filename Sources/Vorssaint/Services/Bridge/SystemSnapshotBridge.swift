// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Backing handler for the `system.snapshot` bridge capability.
///
/// Read-only. Pulls a point-in-time CPU / memory / disk / network summary from
/// the same local sampling primitives the SystemMonitor panel uses, packages
/// them as an inline JSON artifact on a `bridge-receipt.v1`, and never writes
/// anything off the Mac. The capability is `approvalRequired: false` and
/// declares no permissions in the registry.
enum SystemSnapshotBridge {
    static let capabilityId = "system.snapshot"
    static let scope: BridgeScope = .read

    struct Input {
        var requestId: UUID = UUID()
        var caller: BridgeCaller
        var approval: BridgeReceiptApproval? = nil
    }

    /// Always returns exactly one receipt keyed by `requestId`.
    @MainActor
    static func perform(_ input: Input) async -> BridgeReceipt {
        let startedAt = Date()
        let host = BridgeHost(app: AppInfo.name,
                              version: AppInfo.version,
                              registryVersion: Bridge.registryVersion)

        func receipt(_ outcome: BridgeOutcome,
                     artifacts: [BridgeArtifact]? = nil,
                     error: BridgeError? = nil) -> BridgeReceipt {
            BridgeReceipt(requestId: input.requestId.uuidString,
                          capability: capabilityId,
                          outcome: outcome,
                          artifacts: artifacts,
                          permissionsUsed: [],
                          approval: input.approval,
                          error: error,
                          startedAt: startedAt,
                          completedAt: Date(),
                          host: host)
        }

        guard AppFeature.monitorCPU.isAvailable else {
            return receipt(.denied,
                           error: BridgeError(
                            code: "capability_unavailable",
                            message: "The System Monitor feature is not available in this build."))
        }

        let metrics = await sampleMetrics()
        let artifact = BridgeArtifact(
            kind: .json,
            path: nil,
            mimeType: "application/json",
            bytes: nil,
            sha256: nil,
            inline: metrics,
            description: "Point-in-time system snapshot from the local SystemMonitor services.")

        return receipt(.success, artifacts: [artifact])
    }

    /// Two-tick sample so CPU load and network rates have a previous baseline
    /// (same constraint as SystemMonitor / NetworkSampler).
    private static func sampleMetrics() async -> BridgeSystemSnapshotMetrics {
        let network = NetworkSampler()
        let disk = DiskSampler()
        let now0 = ProcessInfo.processInfo.systemUptime
        _ = network.sample(now: now0)
        let cpu0 = readCPUTicks()

        try? await Task.sleep(nanoseconds: 500_000_000)

        let now1 = ProcessInfo.processInfo.systemUptime
        let net = network.sample(now: now1)
        let cpu1 = readCPUTicks()
        let memory = SystemInfo.memoryUsage()
        let diskReading = disk.sample(now: now1, refreshMetadata: true)
        let volume = diskReading.devices.first(where: { $0.mountPath == "/" }) ?? diskReading.devices.first(where: { $0.isInternal }) ?? diskReading.devices.first

        let cpuLoad: Double
        if let cpu0, let cpu1, cpu1.total > cpu0.total {
            cpuLoad = Double(cpu1.busy - cpu0.busy) / Double(cpu1.total - cpu0.total) * 100.0
        } else {
            cpuLoad = 0
        }

        return BridgeSystemSnapshotMetrics(
            cpuLoadPercent: (cpuLoad * 10).rounded() / 10,
            memoryUsedBytes: memory?.used ?? 0,
            memoryTotalBytes: memory?.total ?? ProcessInfo.processInfo.physicalMemory,
            diskFreeBytes: volume?.freeBytes ?? 0,
            diskTotalBytes: volume?.totalBytes ?? 0,
            networkUpBytesPerSec: net.upBytesPerSec ?? 0,
            networkDownBytesPerSec: net.downBytesPerSec ?? 0)
    }

    private struct CPUTicks {
        var busy: UInt64
        var total: UInt64
    }

    private static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
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
}
