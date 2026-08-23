// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// In-memory view of `docs/bridge/capability-registry.v1.json`. The registry is
/// the *what* allowlist: a caller may only invoke a capability that appears
/// here, and only with the scope the registry declares.
public struct CapabilityRegistry: Codable, Sendable {
    public struct Capability: Codable, Sendable {
        public var id: String
        public var title: String
        public var kind: String
        public var scope: BridgeScope
        public var approvalRequired: Bool
        public var permissions: [String]
        public var beta: Bool
        public var description: String?
        public var feature: String?
        public var commandBarActionId: String?
    }

    public struct AppInfo: Codable, Sendable {
        public var bundleId: String
        public var name: String
    }

    public var schema: String
    public var registryVersion: Int
    public var app: AppInfo
    public var permissions: [String]
    public var capabilities: [Capability]

    private var byId: [String: Capability] {
        Dictionary(uniqueKeysWithValues: capabilities.map { ($0.id, $0) })
    }

    public func capability(id: String) -> Capability? {
        capabilities.first { $0.id == id }
    }

    public static func load(from url: URL) throws -> CapabilityRegistry {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CapabilityRegistry.self, from: data)
    }
}
