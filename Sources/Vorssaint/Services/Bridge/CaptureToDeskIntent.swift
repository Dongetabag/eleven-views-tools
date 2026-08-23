// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if canImport(AppIntents)
import AppIntents
import Foundation

/// End-to-end Capture-to-Desk: capture region locally, then attach to a scoped
/// Desk issue after explicit user approval (the App Intent invocation).
@available(macOS 14.0, *)
struct CaptureToDeskIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture to Desk"
    static var description = IntentDescription(
        "Capture a screen region and attach it to a Desk issue. You approve the destination before anything leaves your Mac.")

    @Parameter(title: "Desk company id") var companyId: String
    @Parameter(title: "Desk issue id") var issueId: String
    @Parameter(title: "Desk API token") var accessToken: String
    @Parameter(title: "Desk API base URL") var apiBaseURL: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let approval = BridgeReceiptApproval(
            token: "local-intent-\(UUID().uuidString)",
            grantedBy: BridgeGrantedBy.localUserAction.rawValue)

        let captureInput = ScreenCaptureRegionBridge.Input(
            caller: BridgeCaller(
                id: Bundle.main.bundleIdentifier ?? "io.elevenviews.tools",
                name: AppInfo.name,
                signingIdentifier: Bundle.main.bundleIdentifier),
            approval: approval)

        let captureReceipt = await ScreenCaptureRegionBridge.perform(captureInput)
        guard captureReceipt.outcome == .success,
              let path = captureReceipt.artifacts?.first?.path else {
            throw CaptureIntentError(receipt: captureReceipt)
        }

        let attachInput = DeskAttachmentBridge.Input(
            companyId: companyId,
            issueId: issueId,
            localPath: path,
            apiBaseURL: apiBaseURL ?? DeskAttachmentBridge.defaultApiBase,
            accessToken: accessToken,
            caller: captureInput.caller,
            approval: approval)

        let attachReceipt = await DeskAttachmentBridge.perform(attachInput)
        guard attachReceipt.outcome == .success,
              let inline = attachReceipt.artifacts?.first?.inlineDeskAttachment else {
            throw CaptureIntentError(receipt: attachReceipt)
        }

        let message = "Attached capture to Desk issue \(inline.issueId) (attachment \(inline.attachmentId))."
        return .result(value: inline.attachmentId, dialog: IntentDialog(stringLiteral: message))
    }
}
#endif
