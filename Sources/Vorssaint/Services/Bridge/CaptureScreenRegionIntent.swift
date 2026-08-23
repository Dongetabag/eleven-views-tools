// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if canImport(AppIntents)
import AppIntents
import AppKit
import CoreGraphics
import Foundation

/// The user-facing App Intent for the `screen.captureRegion` bridge capability.
///
/// Invoking it (from Shortcuts, Spotlight or another app's automation) is
/// itself the local-user action that authorises the capture, so the intent
/// mints a fresh approval token and hands it to the bridge handler. It returns
/// the **local file path** of the capture plus the receipt JSON. It never
/// shares the image: keeping the file on the Mac and letting the person move it
/// deliberately is the whole point of the split between `capture` and `share`.
@available(macOS 14.0, *)
struct CaptureScreenRegionIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Screen Region"
    static var description = IntentDescription(
        "Capture a region of the main display and save it locally. The image stays on this Mac; sending it anywhere is a separate, approved step.")

    /// Region to capture, in screen points on the main display. Leaving them
    /// empty captures the whole main display.
    @Parameter(title: "X (points)") var x: Double?
    @Parameter(title: "Y (points)") var y: Double?
    @Parameter(title: "Width (points)") var width: Double?
    @Parameter(title: "Height (points)") var height: Double?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let approval = BridgeReceiptApproval(
            token: "local-intent-\(UUID().uuidString)",
            grantedBy: BridgeGrantedBy.localUserAction.rawValue)

        let input = ScreenCaptureRegionBridge.Input(
            rect: Self.rect(x: x, y: y, width: width, height: height),
            caller: BridgeCaller(
                id: Bundle.main.bundleIdentifier ?? "io.elevenviews.tools",
                name: AppInfo.name,
                teamId: nil,
                signingIdentifier: Bundle.main.bundleIdentifier),
            approval: approval)

        let receipt = await ScreenCaptureRegionBridge.perform(input)

        guard receipt.outcome == .success,
              let path = receipt.artifacts?.first?.path else {
            throw CaptureIntentError(receipt: receipt)
        }

        return .result(
            value: path,
            dialog: "Saved the capture to \(path). It stays on this Mac until you share it.")
    }

    /// Builds a rect only when all four components are supplied and the size is
    /// positive; otherwise returns `nil` for a full main-display capture.
    private static func rect(x: Double?, y: Double?, width: Double?, height: Double?) -> CGRect? {
        guard let x, let y, let width, let height, width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Surfaces a non-success receipt as a readable App Intent error while keeping
/// the machine-readable receipt available for callers that inspect it.
@available(macOS 14.0, *)
struct CaptureIntentError: Error, CustomLocalizedStringResourceConvertible {
    let receipt: BridgeReceipt

    var localizedStringResource: LocalizedStringResource {
        let reason = receipt.error?.message ?? "Capture did not complete (\(receipt.outcome.rawValue))."
        return "\(reason)"
    }
}

/// Makes the capture intent discoverable in Shortcuts and Spotlight. Inert
/// until the app bundle registers App Intents, but declaring it here keeps the
/// capability's user entry point in one place.
@available(macOS 14.0, *)
struct ElevenViewsToolsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureScreenRegionIntent(),
            phrases: ["Capture a screen region with \(.applicationName)"],
            shortTitle: "Capture Screen Region",
            systemImageName: "camera.viewfinder")
    }
}
#endif
