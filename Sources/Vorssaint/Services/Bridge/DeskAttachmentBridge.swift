// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// Backing handler for `share.attachCaptureToDesk`.
///
/// After explicit user approval, uploads a local capture file to a scoped Desk
/// issue via the attachments API and verifies the returned sha256 matches the
/// local file. This is the outbound half of the Capture-to-Desk vertical slice.
enum DeskAttachmentBridge {
    static let capabilityId = "share.attachCaptureToDesk"
    static let scope: BridgeScope = .share
    static let defaultApiBase = "https://desk.elevenviews.io"

    struct Input {
        var requestId: UUID = UUID()
        var companyId: String
        var issueId: String
        var localPath: String
        var apiBaseURL: String = defaultApiBase
        var accessToken: String
        var caller: BridgeCaller
        var approval: BridgeReceiptApproval?
        var description: String = "Eleven Views Tools capture"
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
                            message: "share.attachCaptureToDesk requires a local-user approval token."))
        }

        guard !input.accessToken.isEmpty else {
            return receipt(.failed,
                           error: BridgeError(code: "missing_token",
                                              message: "Desk access token is required."))
        }

        let fileURL = URL(fileURLWithPath: input.localPath)
        guard let fileData = try? Data(contentsOf: fileURL), !fileData.isEmpty else {
            return receipt(.failed,
                           error: BridgeError(code: "missing_file",
                                              message: "Local capture file is missing or empty."))
        }

        let localSha = sha256Hex(fileData)
        guard let base = normalizedBaseURL(input.apiBaseURL),
              let uploadURL = URL(string: "/api/companies/\(input.companyId)/issues/\(input.issueId)/attachments",
                                  relativeTo: base) else {
            return receipt(.failed,
                           error: BridgeError(code: "invalid_api_base",
                                              message: "Desk API base URL is invalid."))
        }

        do {
            let uploaded = try await upload(fileData: fileData,
                                            filename: fileURL.lastPathComponent,
                                            to: uploadURL,
                                            token: input.accessToken,
                                            description: input.description)
            guard uploaded.sha256 == localSha else {
                return receipt(.failed,
                               error: BridgeError(code: "sha_mismatch",
                                                  message: "Desk attachment sha256 did not match the local file."))
            }

            let inline = BridgeDeskAttachmentInline(
                attachmentId: uploaded.id,
                issueId: input.issueId,
                sha256: uploaded.sha256,
                byteSize: uploaded.byteSize,
                contentPath: uploaded.contentPath)
            let artifact = BridgeArtifact(
                kind: .json,
                mimeType: "application/json",
                sha256: uploaded.sha256,
                bytes: uploaded.byteSize,
                inlineDeskAttachment: inline,
                description: "Desk attachment with read-back sha256 verification.")

            return receipt(.success, artifacts: [artifact])
        } catch let error as BridgeError {
            return receipt(.failed, error: error)
        } catch {
            return receipt(.failed,
                           error: BridgeError(code: "upload_failed",
                                              message: error.localizedDescription))
        }
    }

    private struct UploadResponse: Decodable {
        var id: String
        var sha256: String?
        var byteSize: Int?
        var contentPath: String?
    }

    private static func normalizedBaseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return URL(string: defaultApiBase) }
        if trimmed.hasPrefix("http") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    private static func upload(fileData: Data,
                               filename: String,
                               to url: URL,
                               token: String,
                               description: String) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"description\"\r\n\r\n")
        append("\(description)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BridgeError(code: "invalid_response", message: "Desk returned no HTTP response.")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(256), encoding: .utf8) ?? ""
            throw BridgeError(code: "desk_rejected",
                              message: "Desk rejected upload (HTTP \(http.statusCode)): \(snippet)")
        }

        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        guard let sha = decoded.sha256, let bytes = decoded.byteSize else {
            throw BridgeError(code: "invalid_response",
                              message: "Desk upload response missing sha256 or byteSize.")
        }
        return UploadResponse(id: decoded.id, sha256: sha, byteSize: bytes, contentPath: decoded.contentPath)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
