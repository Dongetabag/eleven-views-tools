// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import CryptoKit
import Foundation

/// Backing handler for the `screen.captureRegion` bridge capability.
///
/// It captures a region of the main display through the existing
/// `ScreenshotCaptureEngine`, writes a PNG into the app's owner-only
/// Application Support container, and returns a `bridge-receipt.v1` describing
/// the local file. Nothing is ever transferred off the Mac here: the receipt's
/// artifact is a local path, and moving it anywhere is a separate,
/// user-approved `share`-scope capability. The capability is `approvalRequired`
/// in the registry, so a valid local-user approval token must accompany every
/// request or the handler refuses with `needs_approval`.
enum ScreenCaptureRegionBridge {
    static let capabilityId = "screen.captureRegion"
    static let scope: BridgeScope = .capture

    /// A capture request. `rect` is expressed in top-left screen points on the
    /// main display; `nil` captures the whole main display. The rect is
    /// converted to backing pixels and clamped to the display by the engine.
    struct Input {
        var requestId: UUID = UUID()
        var rect: CGRect?
        var caller: BridgeCaller
        var approval: BridgeReceiptApproval?
        var includePointer: Bool = false
    }

    /// Runs the capture and always produces exactly one receipt, keyed back by
    /// `requestId`. Refusals (missing approval, missing permission, unavailable
    /// feature) are reported as receipts, not thrown, so callers get uniform
    /// evidence for every request.
    @MainActor
    static func perform(_ input: Input) async -> BridgeReceipt {
        let startedAt = Date()
        let host = BridgeHost(app: AppInfo.name,
                              version: AppInfo.version,
                              registryVersion: Bridge.registryVersion)

        func receipt(_ outcome: BridgeOutcome,
                     artifacts: [BridgeArtifact]? = nil,
                     permissionsUsed: [String] = [],
                     error: BridgeError? = nil) -> BridgeReceipt {
            BridgeReceipt(requestId: input.requestId.uuidString,
                          capability: capabilityId,
                          outcome: outcome,
                          artifacts: artifacts,
                          permissionsUsed: permissionsUsed,
                          approval: input.approval,
                          error: error,
                          startedAt: startedAt,
                          completedAt: Date(),
                          host: host)
        }

        // 1. Approval gate. The capability is approvalRequired; a locally
        //    invoked App Intent mints the token from the user's own action.
        guard let approval = input.approval, !approval.token.isEmpty else {
            return receipt(.needsApproval,
                           error: BridgeError(
                            code: "approval_required",
                            message: "screen.captureRegion requires a local-user approval token."))
        }

        // 2. The backing feature must be enabled in this build.
        guard AppFeature.screenshot.isAvailable else {
            return receipt(.denied,
                           error: BridgeError(
                            code: "capability_unavailable",
                            message: "The Screenshot feature is not available in this build."))
        }

        // 3. Screen Recording must already be granted. We do not request it
        //    here — prompting is a user-facing step the App Intent owns.
        guard CGPreflightScreenCaptureAccess() else {
            return receipt(.needsPermission,
                           error: BridgeError(
                            code: "screen_recording_denied",
                            message: "Screen Recording permission is required to capture the screen."))
        }

        // 4. Resolve the display and the pixel rect to capture.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return receipt(.failed,
                           error: BridgeError(code: "no_display",
                                              message: "No display is available to capture."))
        }
        let displayID = screen.displayID
        guard displayID != 0 else {
            return receipt(.failed,
                           error: BridgeError(code: "no_display",
                                              message: "The main display is not capturable."))
        }

        let scale = screen.backingScaleFactor
        let hideOwnWindows = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotHideVorssaintWindows)
        let protectedWindowIDs = ScreenshotService.shared.protectedWindowIDsForCapture

        let image: CGImage?
        if let rect = input.rect {
            let pixelRect = CGRect(x: rect.minX * scale,
                                   y: rect.minY * scale,
                                   width: rect.width * scale,
                                   height: rect.height * scale)
            image = await ScreenshotCaptureEngine.captureDisplayRegion(
                displayID: displayID,
                pixelRect: pixelRect,
                includePointer: input.includePointer,
                hideVorssaintWindows: hideOwnWindows,
                protectedWindowIDs: protectedWindowIDs)
        } else {
            image = await ScreenshotCaptureEngine.captureDisplay(
                displayID,
                includePointer: input.includePointer,
                hideVorssaintWindows: hideOwnWindows,
                protectedWindowIDs: protectedWindowIDs)
        }

        guard let captured = image else {
            return receipt(.failed,
                           permissionsUsed: [AppPermission.screenRecording.rawValue],
                           error: BridgeError(code: "capture_failed",
                                              message: "The capture returned no image."))
        }

        // 5. Encode and write locally, owner-only.
        guard let png = ScreenshotRenderer.pngData(from: captured) else {
            return receipt(.failed,
                           permissionsUsed: [AppPermission.screenRecording.rawValue],
                           error: BridgeError(code: "encode_failed",
                                              message: "Could not encode the capture as PNG."))
        }

        guard let url = writeCapture(png) else {
            return receipt(.failed,
                           permissionsUsed: [AppPermission.screenRecording.rawValue],
                           error: BridgeError(code: "write_failed",
                                              message: "Could not write the capture to the local container."))
        }

        let artifact = BridgeArtifact(
            kind: .image,
            path: url.path,
            mimeType: "image/png",
            bytes: png.count,
            sha256: Self.sha256Hex(png),
            description: "Captured region. Stays local until an explicit share capability moves it.")

        return receipt(.success,
                       artifacts: [artifact],
                       permissionsUsed: [AppPermission.screenRecording.rawValue])
    }

    /// Writes the PNG into `<Application Support>/<bundle id>/captures` with
    /// owner-only permissions and a dated `region-YYYYMMDD-HHMMSS.png` name,
    /// matching the receipt example. Returns `nil` if the container is
    /// unavailable or the write fails.
    private static func writeCapture(_ data: Data) -> URL? {
        guard let container = PrivateFileStore.containerURL else { return nil }
        let directory = container.appendingPathComponent("captures", isDirectory: true)
        guard PrivateFileStore.createDirectory(at: directory) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "region-\(formatter.string(from: Date())).png"
        let url = directory.appendingPathComponent(name)
        guard PrivateFileStore.write(data, to: url) else { return nil }
        return url
    }

    /// Lowercase hex SHA-256, matching the `^[a-f0-9]{64}$` the receipt schema
    /// requires for artifact digests.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
