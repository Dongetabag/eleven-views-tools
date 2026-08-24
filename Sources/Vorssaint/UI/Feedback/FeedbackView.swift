// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct FeedbackView: View {
    let onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var kind: FeedbackKind
    @State private var message = ""
    @State private var includeDiagnostics = false
    @State private var errorMessage: String?

    private let diagnostics = FeedbackDiagnostics.current()

    init(initialKind: FeedbackKind = .bug, onClose: @escaping () -> Void) {
        _kind = State(initialValue: initialKind)
        self.onClose = onClose
    }

    private var strings: FeedbackStrings { FeatureStrings.feedback(l10n.language) }
    private var count: Int { message.utf16.count }
    private var canSend: Bool {
        let trimmedCount = message.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        return trimmedCount >= 10 && count <= 2_000
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
        }
        .frame(width: 600, height: 650)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text(strings.windowTitle)
                .font(.title2.weight(.semibold))
            Spacer()
            Button(strings.done, action: onClose)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("", selection: $kind) {
                        Text(strings.bugTitle).tag(FeedbackKind.bug)
                        Text(strings.featureTitle).tag(FeedbackKind.feature)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(strings.messageLabel)
                            .font(.headline)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $message)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                            if message.isEmpty {
                                Text(kind == .bug ? strings.bugPlaceholder : strings.featurePlaceholder)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 11)
                                    .padding(.top, 6)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(minHeight: 145)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(.separator, lineWidth: 1)
                        }
                        Text(String(format: strings.charactersFormat, count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(count > 2_000 ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(strings.includeDiagnostics, isOn: $includeDiagnostics)
                        Text(strings.includeDiagnosticsCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label(strings.whatSentTitle, systemImage: "eye")
                            .font(.headline)
                        Label(strings.whatSentBasic, systemImage: "text.alignleft")
                        if includeDiagnostics {
                            Label(strings.whatSentDiagnostics, systemImage: "info.circle")
                            diagnosticsPreview
                                .padding(.leading, 26)
                        }
                        Divider()
                        Label("Opens a Mail draft addressed to \(AppInfo.supportEmail). Nothing leaves Eleven Views Tools until you send it from Mail.",
                              systemImage: "hand.raised")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("Your message remains in your mail account according to your email provider's retention settings.",
                              systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(24)
            }

            Divider()
            HStack(spacing: 12) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Open email draft") { send() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .onChange(of: message) { oldValue, newValue in
            if newValue.utf16.count > 2_000 {
                var limited = ""
                var units = 0
                for character in newValue {
                    let piece = String(character)
                    let pieceUnits = piece.utf16.count
                    if units + pieceUnits > 2_000 { break }
                    limited.append(contentsOf: piece)
                    units += pieceUnits
                }
                message = limited.isEmpty ? oldValue : limited
            }
            if errorMessage != nil { errorMessage = nil }
        }
    }

    private var diagnosticsPreview: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            diagnosticRow("Eleven Views Tools", "\(diagnostics.appVersion) (\(diagnostics.appBuild))")
            diagnosticRow("macOS", diagnostics.macOS)
            if let model = diagnostics.macModel { diagnosticRow("Mac", model) }
            diagnosticRow(l10n.s.languageLabel, diagnostics.language)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.tertiary)
            Text(value).textSelection(.enabled)
        }
    }

    private func send() {
        guard canSend else { return }
        errorMessage = nil
        guard let url = FeedbackService.draftURL(
            kind: kind,
            message: message,
            diagnostics: includeDiagnostics ? diagnostics : nil
        ), NSWorkspace.shared.open(url) else {
            errorMessage = strings.genericError
            return
        }
        message = ""
        onClose()
    }
}
