// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Desk bridge credentials and HTTP helpers for `share.attachToDeskIssue`.
///
/// Credentials live owner-only under Application Support. Nothing is sent until
/// the user approves a share-scoped bridge request with a destination preview.
enum DeskBridgeSupport {
    static let productionApiURL = URL(string: "https://desk.elevenviews.io")!
    static let developerBundleIdentifier = "io.elevenviews.tools.dev"
    static let maximumUploadBytes = 25 * 1_024 * 1_024

    struct Credentials: Codable, Equatable {
        var apiUrl: URL
        var companyId: String
        var apiToken: String
    }

    struct AttachmentResult: Codable, Equatable {
        var attachmentId: String
        var issueId: String
        var sha256: String
        var byteSize: Int
        var contentPath: String
        var originalFilename: String
    }

    enum BridgeError: Error {
        case notConfigured
        case invalidParameters
        case fileMissing
        case fileTooLarge
        case uploadFailed(String)
        case readBackFailed(String)
        case verificationFailed
    }

    static func credentials(developerOverride: Credentials?) -> Credentials? {
        if let developerOverride,
           Bundle.main.bundleIdentifier == developerBundleIdentifier {
            return developerOverride
        }
        return loadStoredCredentials()
    }

    static func loadStoredCredentials() -> Credentials? {
        guard let url = credentialsURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Credentials.self, from: data),
              !decoded.apiToken.isEmpty,
              !decoded.companyId.isEmpty
        else { return nil }
        return decoded
    }

    static func saveCredentials(_ credentials: Credentials) -> Bool {
        guard let url = credentialsURL,
              let directory = credentialsURL?.deletingLastPathComponent(),
              PrivateFileStore.createDirectory(at: directory),
              let data = try? JSONEncoder().encode(credentials)
        else { return false }
        return PrivateFileStore.write(data, to: url)
    }

    private static var credentialsURL: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("desk-bridge", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    static func uploadAttachment(fileURL: URL,
                                 issueId: String,
                                 credentials: Credentials,
                                 runId: String? = nil) async throws -> AttachmentResult {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty, data.count <= maximumUploadBytes else {
            throw BridgeError.fileTooLarge
        }

        let boundary = "ElevenViewsBridge-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: \(mimeType(for: fileURL))\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        let endpoint = credentials.apiUrl
            .appendingPathComponent("api/companies/\(credentials.companyId)/issues/\(issueId)/attachments")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let runId, !runId.isEmpty {
            request.setValue(runId, forHTTPHeaderField: "X-Paperclip-Run-Id")
        }
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let detail = String(data: responseData, encoding: .utf8) ?? "HTTP error"
            throw BridgeError.uploadFailed(detail)
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let attachmentId = json["id"] as? String,
              let sha256 = json["sha256"] as? String,
              let byteSize = json["byteSize"] as? Int,
              let contentPath = json["contentPath"] as? String,
              let originalFilename = json["originalFilename"] as? String
        else {
            throw BridgeError.uploadFailed("Unexpected upload response shape.")
        }

        return AttachmentResult(attachmentId: attachmentId,
                                issueId: issueId,
                                sha256: sha256,
                                byteSize: byteSize,
                                contentPath: contentPath,
                                originalFilename: originalFilename)
    }

    static func verifyReadBack(result: AttachmentResult,
                             credentials: Credentials,
                             expectedSha256: String) async throws {
        guard let url = URL(string: result.contentPath, relativeTo: credentials.apiUrl)?.absoluteURL else {
            throw BridgeError.readBackFailed("Invalid attachment content path.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BridgeError.readBackFailed("Could not download attachment content.")
        }
        guard ScreenCaptureRegionBridge.sha256Hex(data) == expectedSha256,
              ScreenCaptureRegionBridge.sha256Hex(data) == result.sha256
        else {
            throw BridgeError.verificationFailed
        }
    }

    private static func mimeType(for url: URL) -> String {
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
