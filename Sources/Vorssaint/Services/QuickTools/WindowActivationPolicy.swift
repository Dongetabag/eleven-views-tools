// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct WindowActivationRetention {
    private(set) var count = 0

    mutating func retain() -> Bool {
        count += 1
        return count == 1
    }

    mutating func release() -> Bool {
        guard count > 0 else { return false }
        count -= 1
        return count == 0
    }
}

/// User-facing tools may ask for regular-app activation before presenting a
/// window. Eleven Views Tools now remains a regular Dock app permanently, so a
/// balanced release only updates retention state and never hides the app again.
enum WindowActivationPolicy {
    private static var retention = WindowActivationRetention()

    static func retain() {
        _ = retention.retain()
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    static func release() {
        _ = retention.release()
    }
}
