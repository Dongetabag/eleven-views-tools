// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Backing handler for the `share.attachToDeskIssue` bridge capability.
///
/// Uploads a local file to a scoped Desk issue via the Paperclip attachments
/// API, read-back verifies the SHA-256, and returns a receipt. This is the
/// only bridge path that moves bytes off the Mac; it is `approvalRequired` and
/// `share`-scoped so the user must explicitly approve the destination.
enum AttachToDeskIssueBridge {
    static let capabilityId = "share.attachToDeskIssue"
    static let scope: BridgeScope = .share

    struct Input {
        var requestId: UUID = UUID()
        var issueId: String
        var filePath: String
        var caller: BridgeCaller
        var approval: BridgeReceiptApproval?
        /// Harness-only overrides; ignored outside the developer bundle.
        var credentialOverride: DeskBridgeSupport.Credentials?
        var runId: String?
    }

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

        guard let approval = input.approval, !approval.token.isEmpty else {
            return receipt(.needsApproval,
                           error: BridgeError(
                            code: "approval_required",
                            message: "share.attachToDeskIssue requires a local-user approval token."))
        }

        let trimmedIssueId = input.issueId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = input.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIssueId.isEmpty, !trimmedPath.isEmpty else {
            return receipt(.failed,
                           error: BridgeError(code: "invalid_parameters",
                                              message: "issueId and filePath are required."))
        }

        let fileURL = URL(fileURLWithPath: trimmedPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return receipt(.failed,
                           error: BridgeError(code: "file_missing",
                                              message: "The file to attach does not exist."))
        }

        guard let credentials = DeskBridgeSupport.credentials(developerOverride: input.credentialOverride) else {
            return receipt(.failed,
                           error: BridgeError(code: "desk_not_configured",
                                              message: "Desk bridge credentials are not configured on this Mac."))
        }

        do {
            let localData = try Data(contentsOf: fileURL)
            let localSha = ScreenCaptureRegionBridge.sha256Hex(localData)
            let uploaded = try await DeskBridgeSupport.uploadAttachment(
                fileURL: fileURL,
                issueId: trimmedIssueId,
                credentials: credentials,
                runId: input.runId)
            try await DeskBridgeSupport.verifyReadBack(result: uploaded,
                                                       credentials: credentials,
                                                       expectedSha256: localSha)

            let artifact = BridgeArtifact(
                kind: .file,
                path: fileURL.path,
                mimeType: DeskBridgeSupport.mimeTypePublic(for: fileURL),
                bytes: uploaded.byteSize,
                sha256: uploaded.sha256,
                description: "Attached to Desk issue \(uploaded.issueId) as \(uploaded.attachmentId). Read-back verified.")

            return receipt(.success, artifacts: [artifact])
        } catch let error as DeskBridgeSupport.BridgeError {
            switch error {
            case .notConfigured:
                return receipt(.failed,
                               error: BridgeError(code: "desk_not_configured",
                                                  message: "Desk bridge credentials are not configured."))
            case .fileTooLarge:
                return receipt(.failed,
                               error: BridgeError(code: "file_too_large",
                                                  message: "The file exceeds the Desk upload limit."))
            case .verificationFailed:
                return receipt(.failed,
                               error: BridgeError(code: "readback_mismatch",
                                                  message: "Read-back SHA-256 did not match the local file."))
            case .uploadFailed(let detail):
                return receipt(.failed,
                               error: BridgeError(code: "upload_failed", message: detail))
            case .readBackFailed(let detail):
                return receipt(.failed,
                               error: BridgeError(code: "readback_failed", message: detail))
            default:
                return receipt(.failed,
                               error: BridgeError(code: "attach_failed",
                                                  message: "Could not attach the file to Desk."))
            }
        } catch {
            return receipt(.failed,
                           error: BridgeError(code: "attach_failed",
                                              message: error.localizedDescription))
        }
    }
}

private extension DeskBridgeSupport {
    static func mimeTypePublic(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
