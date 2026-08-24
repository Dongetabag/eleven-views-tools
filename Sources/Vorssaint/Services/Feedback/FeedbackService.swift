// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeedbackKind: String, Codable, CaseIterable {
    case bug
    case feature
}

struct FeedbackDiagnostics: Codable {
    let appVersion: String
    let appBuild: String
    let macOS: String
    let macModel: String?
    let language: String
    let isBeta: Bool
    let updateChannel: String

    static func current() -> FeedbackDiagnostics {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let isBeta = AppInfo.isBeta
        let channel = AppInfo.isDeveloperBuild ? "developer" : (isBeta ? "beta" : (UpdateService.shared.includeBetaUpdates ? "beta-opt-in" : "stable"))
        return FeedbackDiagnostics(
            appVersion: AppInfo.version,
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            macModel: modelIdentifier,
            language: L10n.shared.language.rawValue,
            isBeta: isBeta,
            updateChannel: channel
        )
    }

    private static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }()
}

enum FeedbackService {
    /// Creates a local Mail draft addressed to Eleven Views. The app never
    /// uploads feedback to an unowned endpoint; the person can inspect and edit
    /// the complete message in their mail client before choosing to send it.
    static func draftURL(kind: FeedbackKind,
                         message: String,
                         diagnostics: FeedbackDiagnostics?) -> URL? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count >= 10, trimmed.utf16.count <= 2_000 else { return nil }

        let kindTitle = kind == .bug ? "Bug report" : "Feature request"
        var body = [
            trimmed,
            "",
            "---",
            "Sent from \(AppInfo.name)",
        ]
        if let diagnostics {
            body.append(contentsOf: [
                "Version: \(diagnostics.appVersion) (\(diagnostics.appBuild))",
                "macOS: \(diagnostics.macOS)",
                "Mac: \(diagnostics.macModel ?? "Not included")",
                "Language: \(diagnostics.language)",
                "Channel: \(diagnostics.updateChannel)",
            ])
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppInfo.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(AppInfo.name) — \(kindTitle)"),
            URLQueryItem(name: "body", value: body.joined(separator: "\n")),
        ]
        return components.url
    }
}
