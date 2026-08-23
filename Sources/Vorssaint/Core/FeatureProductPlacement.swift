// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Eleven Views

import Foundation

/// Stable customer outcomes used to organize the product. Individual tools
/// remain implementation details; these are the jobs a person comes to the
/// app to complete.
enum FeatureOutcome: String, CaseIterable, Codable {
    case capture
    case workspace
    case create
    case meeting
    case health
    case agent
    case advanced

    var title: String {
        switch self {
        case .capture: return "Capture"
        case .workspace: return "Workspace"
        case .create: return "Create"
        case .meeting: return "Meeting"
        case .health: return "Mac Health"
        case .agent: return "Ask Atlas"
        case .advanced: return "Advanced Tools"
        }
    }
}

/// Controls how prominently an existing capability appears. This does not
/// disable anything; it keeps specialist controls from competing with the
/// small set of outcomes that should define the first-run experience.
enum FeatureExposureTier: String, CaseIterable, Codable {
    case primary
    case contextual
    case advanced
}

struct FeatureProductPlacement: Equatable {
    let outcome: FeatureOutcome
    let exposure: FeatureExposureTier
}

extension AppFeature {
    /// Exhaustive by design. Adding a native capability requires deciding the
    /// customer outcome it serves and how prominently it should be presented.
    var productPlacement: FeatureProductPlacement {
        switch self {
        // Capture: turn anything on screen into a useful local artifact.
        case .clipboardHistory, .screenOCR, .screenshot, .screenRecorder:
            return FeatureProductPlacement(outcome: .capture, exposure: .primary)
        case .pastePlain, .shelf, .urlCleaner, .colorPicker:
            return FeatureProductPlacement(outcome: .capture, exposure: .contextual)

        // Workspace: prepare the Mac for the work the person is about to do.
        case .windowLayout:
            return FeatureProductPlacement(outcome: .workspace, exposure: .primary)
        case .switcher, .dockPreview, .dockClick, .windowMaximizer,
             .textSnippets, .finderCutPaste, .finderRename, .musicBlock,
             .keepAwake, .brightness, .quickLauncher, .quickToggles,
             .radialMenu, .scratchpad:
            return FeatureProductPlacement(outcome: .workspace, exposure: .contextual)

        // Create: make media and files ready for their destination.
        case .mediaTools:
            return FeatureProductPlacement(outcome: .create, exposure: .primary)

        // Meeting: make camera, microphone, output and app sound dependable.
        case .mixer, .soundOutputSwitcher, .micMute, .cameraPreview:
            return FeatureProductPlacement(outcome: .meeting, exposure: .contextual)

        // Health: explain what is wrong and surface safe recommendations.
        case .cleaner:
            return FeatureProductPlacement(outcome: .health, exposure: .primary)
        case .cleaningMode, .uninstaller, .homebrew, .appUpdates,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork,
             .monitorDisk, .monitorPower:
            return FeatureProductPlacement(outcome: .health, exposure: .contextual)

        // Agent: the human-facing entrance to governed Atlas proposals.
        case .commandBar:
            return FeatureProductPlacement(outcome: .agent, exposure: .primary)

        // Advanced: valuable specialist controls that should be opt-in or
        // reached from a relevant workflow instead of defining the homepage.
        case .autoQuit, .scrollInverter, .focusFollowsMouse, .smoothScroll,
             .mouseNavigation, .mouseButtonShortcuts, .middleClick,
             .keyboardDebounce, .superKey, .diskImageInstaller,
             .extraBrightness, .killProcess, .fanControl:
            return FeatureProductPlacement(outcome: .advanced, exposure: .advanced)
        }
    }
}
