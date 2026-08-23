// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

/// Desk credentials and HTTP helpers for `share.attachToDeskIssue`.
///
/// Production credentials live in the user's macOS Keychain. Production
/// requests are pinned to `desk.elevenviews.io`; only the developer bundle may
/// inject a different endpoint for a local harness.
enum DeskBridgeSupport {
    static let productionApiURL = URL(string: "https://desk.elevenviews.io")!
    static let developerBundleIdentifier = "io.elevenviews.tools.dev"
    static let keychainService = "io.elevenviews.tools.desk-bridge"
    static let maximumUploadBytes = 25 * 1_024 * 1_024

    struct Credentials: Equatable {
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

    /// Uses a harness override only for the developer bundle. Release builds
    /// always load a production-host credential from Keychain.
    static func credentials(developerOverride: Credentials?) -> Credentials? {
        if let developerOverride,
           Bundle.main.bundleIdentifier == developerBundleIdentifier,
           validDeveloperCredentials(developerOverride) {
            return developerOverride
        }
        return loadStoredCredentials()
    }

    static func loadStoredCredentials() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let result = item as? [String: Any],
              let companyId = result[kSecAttrAccount as String] as? String,
              let tokenData = result[kSecValueData as String] as? Data,
              let token = String(data: tokenData, encoding: .utf8),
              validCompanyId(companyId),
              !token.isEmpty
        else { return nil }

        return Credentials(apiUrl: productionApiURL,
                           companyId: companyId,
                           apiToken: token)
    }

    /// Stores a single Desk company credential in the macOS Keychain. This is
    /// intentionally not a JSON file under Application Support.
    static func saveCredentials(_ credentials: Credentials) -> Bool {
        guard sameOrigin(credentials.apiUrl, productionApiURL),
              validCompanyId(credentials.companyId),
              !credentials.apiToken.isEmpty,
              let tokenData = credentials.apiToken.data(using: .utf8)
        else { return false }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        SecItemDelete(identity as CFDictionary)

        var item = identity
        item[kSecAttrAccount as String] = credentials.companyId
        item[kSecAttrLabel as String] = "Eleven Views Desk bridge"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecValueData as String] = tokenData
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func removeStoredCredentials() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func validIssueId(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return issueIdentifierRegex.firstMatch(in: value, range: range) != nil
    }

    static func readLocalFile(at fileURL: URL) throws -> Data {
        let standardized = fileURL.standardizedFileURL
        guard standardized.isFileURL,
              let values = try? standardized.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else { throw BridgeError.fileMissing }

        guard let size = values.fileSize, size > 0 else { throw BridgeError.fileMissing }
        guard size <= maximumUploadBytes else { throw BridgeError.fileTooLarge }

        let data = try Data(contentsOf: standardized, options: .mappedIfSafe)
        guard !data.isEmpty else { throw BridgeError.fileMissing }
        return data
    }

    static func uploadAttachment(fileData: Data,
                                 filename: String,
                                 mimeType: String,
                                 issueId: String,
                                 credentials: Credentials,
                                 runId: String? = nil) async throws -> AttachmentResult {
        guard !fileData.isEmpty, fileData.count <= maximumUploadBytes else {
            throw BridgeError.fileTooLarge
        }
        guard validIssueId(issueId), validProductionCredentials(credentials) else {
            throw BridgeError.invalidParameters
        }

        let boundary = "ElevenViewsBridge-\(UUID().uuidString)"
        let safeFilename = sanitizedFilename(filename)
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        let endpoint = credentials.apiUrl
            .appendingPathComponent("api")
            .appendingPathComponent("companies")
            .appendingPathComponent(credentials.companyId)
            .appendingPathComponent("issues")
            .appendingPathComponent(issueId)
            .appendingPathComponent("attachments")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let runId, !runId.isEmpty {
            request.setValue(runId, forHTTPHeaderField: "X-Paperclip-Run-Id")
        }
        request.httpBody = body

        let (responseData, response) = try await pinnedSessionData(
            for: request,
            allowedOrigin: credentials.apiUrl)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BridgeError.uploadFailed(responseSnippet(responseData))
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
                               expectedSha256: String,
                               expectedByteSize: Int) async throws {
        guard validProductionCredentials(credentials),
              let url = URL(string: result.contentPath, relativeTo: credentials.apiUrl)?.absoluteURL,
              sameOrigin(url, credentials.apiUrl)
        else {
            throw BridgeError.readBackFailed("Invalid attachment content path.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await pinnedSessionData(
            for: request,
            allowedOrigin: credentials.apiUrl)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BridgeError.readBackFailed("Could not download attachment content.")
        }
        guard data.count == expectedByteSize,
              result.byteSize == expectedByteSize,
              ScreenCaptureRegionBridge.sha256Hex(data) == expectedSha256,
              result.sha256 == expectedSha256
        else {
            throw BridgeError.verificationFailed
        }
    }

    static func mimeType(for url: URL) -> String {
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

    private static let issueIdentifierRegex = try! NSRegularExpression(
        pattern: "^(?:[A-Z][A-Z0-9]{1,11}-[0-9]+|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12})$")

    private static func validCompanyId(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    private static func validDeveloperCredentials(_ credentials: Credentials) -> Bool {
        guard let scheme = credentials.apiUrl.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              validCompanyId(credentials.companyId),
              !credentials.apiToken.isEmpty
        else { return false }
        return true
    }

    private static func validProductionCredentials(_ credentials: Credentials) -> Bool {
        if Bundle.main.bundleIdentifier == developerBundleIdentifier {
            return validDeveloperCredentials(credentials)
        }
        return sameOrigin(credentials.apiUrl, productionApiURL)
            && validCompanyId(credentials.companyId)
            && !credentials.apiToken.isEmpty
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && normalizedPort(lhs) == normalizedPort(rhs)
            && lhs.user == nil && lhs.password == nil
    }

    private static func normalizedPort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    private static func sanitizedFilename(_ value: String) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> Character in
            if scalar.value < 0x20 || scalar.value == 0x22 || scalar.value == 0x5C {
                return "_"
            }
            return Character(scalar)
        }
        let filename = String(cleaned).prefix(180)
        return filename.isEmpty ? "attachment" : String(filename)
    }

    private static func responseSnippet(_ data: Data) -> String {
        let value = String(data: data.prefix(256), encoding: .utf8) ?? "HTTP error"
        return value.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func pinnedSessionData(for request: URLRequest,
                                          allowedOrigin: URL) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = SameOriginRedirectDelegate(allowedOrigin: allowedOrigin)
        let session = URLSession(configuration: configuration,
                                 delegate: delegate,
                                 delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }
}

private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let scheme: String?
    private let host: String?
    private let port: Int?

    init(allowedOrigin: URL) {
        scheme = allowedOrigin.scheme?.lowercased()
        host = allowedOrigin.host?.lowercased()
        port = allowedOrigin.port ?? (scheme == "https" ? 443 : 80)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url else {
            completionHandler(nil)
            return
        }
        let nextPort = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
        let isAllowed = url.scheme?.lowercased() == scheme
            && url.host?.lowercased() == host
            && nextPort == port
            && url.user == nil && url.password == nil
        completionHandler(isAllowed ? request : nil)
    }
}
