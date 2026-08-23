// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if canImport(AppIntents)
import AppIntents
import Foundation

/// User-facing App Intent for `share.attachToDeskIssue`.
///
/// Invoking it mints the local-user approval token, shows the destination in
/// the dialog, uploads the file to the scoped Desk issue, read-back verifies
/// the SHA-256, and returns the attachment id plus receipt JSON.
@available(macOS 14.0, *)
struct AttachToDeskIssueIntent: AppIntent {
    static var title: LocalizedStringResource = "Attach File to Desk Issue"
    static var description = IntentDescription(
        "Upload a local file to a Desk issue after you approve the destination. The file leaves this Mac only through this explicit share step.")

    @Parameter(title: "Desk Issue ID") var issueId: String
    @Parameter(title: "Local File Path") var filePath: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let approval = BridgeReceiptApproval(
            token: "local-intent-\(UUID().uuidString)",
            grantedBy: BridgeGrantedBy.localUserAction.rawValue)

        let input = AttachToDeskIssueBridge.Input(
            issueId: issueId,
            filePath: filePath,
            caller: BridgeCaller(
                id: Bundle.main.bundleIdentifier ?? "io.elevenviews.tools",
                name: AppInfo.name,
                teamId: nil,
                signingIdentifier: Bundle.main.bundleIdentifier),
            approval: approval)

        let receipt = await AttachToDeskIssueBridge.perform(input)

        guard receipt.outcome == .success,
              let artifact = receipt.artifacts?.first else {
            throw CaptureIntentError(receipt: receipt)
        }

        let attachmentId = artifact.description?
            .components(separatedBy: " as ")
            .last?
            .replacingOccurrences(of: ". Read-back verified.", with: "") ?? artifact.sha256 ?? "attached"

        return .result(
            value: attachmentId,
            dialog: "Attached \(URL(fileURLWithPath: filePath).lastPathComponent) to Desk issue \(issueId). Read-back verified.")
    }
}
#endif
