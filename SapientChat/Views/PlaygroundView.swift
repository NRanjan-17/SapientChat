// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// The Playground tab: compose an API request, run it on this device and
/// read the reply, the raw response and the timing; copy it as code.
struct PlaygroundView: View {
    @Bindable var viewModel: PlaygroundViewModel
    let makeSelector: (String, @escaping (String) -> Void) -> ModelSelectorViewModel
    /// The context window of the picked model, for the token estimate.
    let contextWindow: (String) -> Int?
    @State private var copied: PlaygroundViewModel.Snippet?
    @State private var showsTools = false

    var body: some View {
        NavigationStack {
            SetupResultsLayout {
                request
                runSection
            } results: {
                response
            }
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .navigationTitle("Playground")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(PlaygroundViewModel.Snippet.allCases) { snippet in
                            Button("Copy as \(snippet.rawValue)") { copy(snippet) }
                        }
                        Divider()
                        Button("Reset", systemImage: "arrow.counterclockwise", role: .destructive, action: viewModel.reset)
                    } label: {
                        Label("Copy as Code", systemImage: copied == nil ? "chevron.left.forwardslash.chevron.right" : "checkmark")
                    }
                }
            }
            .sensoryFeedback(.success, trigger: copied) { _, new in new != nil }
        }
    }

    // MARK: Request

    @ViewBuilder private var request: some View {
        Section {
            Picker("Editor", selection: editor) {
                Text("Form").tag(false)
                Text("JSON").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .disabled(viewModel.isRunning)

        if viewModel.isRaw {
            rawEditor
        } else {
            form
        }
    }

    @ViewBuilder private var form: some View {
        Section {
            ModelPickerField(title: "Model", selection: viewModel.model, makeSelector: makeSelector) { alias in
                viewModel.model = alias
            }
        }
        .disabled(viewModel.isRunning)

        Section("System prompt") {
            TextField("Optional instructions for the model", text: $viewModel.systemPrompt, axis: .vertical)
                .lineLimit(1...6)
        }

        Section {
            ForEach($viewModel.messages) { $message in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("Role", selection: $message.role) {
                            ForEach(PlaygroundViewModel.roles, id: \.self) { role in
                                Text(role).tag(role)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Spacer()
                        if viewModel.messages.count > 1 {
                            Button("Remove Message", systemImage: "minus.circle") { viewModel.remove(message) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    TextField("Message", text: $message.text, axis: .vertical)
                        .lineLimit(1...10)
                }
            }
            Button("Add Message", systemImage: "plus", action: viewModel.addMessage)
        } header: {
            Text("Messages")
        } footer: {
            Text(tokenFooter)
        }

        Section {
            Picker("Max tokens", selection: $viewModel.maxTokens) {
                ForEach(PlaygroundViewModel.maxTokenChoices, id: \.self) { choice in
                    Text(choice == 0 ? "No limit" : choice.formatted()).tag(choice)
                }
            }
            Toggle("Stream", isOn: $viewModel.streams)
            Toggle("JSON reply", isOn: $viewModel.wantsJSON)
            LabeledContent("Stop") {
                TextField("One per line", text: $viewModel.stopText, axis: .vertical)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            DisclosureGroup("Tools", isExpanded: $showsTools) {
                TextField("[{\"type\": \"function\", \"function\": {…}}]", text: $viewModel.toolsText, axis: .vertical)
                    .font(.footnote.monospaced())
                    .lineLimit(3...12)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let problem = viewModel.toolsProblem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Temperature and sampling are set per model (Models → ⋯ → Model Settings). JSON replies and tool calls are asked for in the prompt and checked afterwards; the engine can't force a format, so small models miss it sometimes.")
        }
    }

    @ViewBuilder private var rawEditor: some View {
        Section {
            Picker("Method", selection: $viewModel.method) {
                Text("POST").tag("POST")
                Text("GET").tag("GET")
            }
            LabeledContent("Path") {
                TextField("/v1/…", text: $viewModel.path)
                    .multilineTextAlignment(.trailing)
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Request")
        }
        if viewModel.method != "GET" {
            Section {
                TextField("{ }", text: $viewModel.rawBody, axis: .vertical)
                    .font(.footnote.monospaced())
                    .lineLimit(6...24)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Body")
            } footer: {
                Text("Sent as typed. \(tokenFooter)")
            }
        }
    }

    private var runSection: some View {
        Section {
            if viewModel.isRunning {
                Button("Stop", systemImage: "stop.fill", role: .cancel, action: viewModel.cancel)
            } else {
                Button("Run", systemImage: "play.fill", action: viewModel.run)
                    .disabled(!viewModel.canRun)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        } footer: {
            Text("Runs on this device, through the same code the API server uses. It works with the server off.")
        }
    }

    // MARK: Response

    @ViewBuilder private var response: some View {
        if viewModel.isRunning || viewModel.metrics != nil || !viewModel.reply.isEmpty || viewModel.errorMessage != nil {
            Section("Response") {
                if let metrics = viewModel.metrics {
                    LabeledContent("Status") {
                        Text(metrics.status, format: .number.grouping(.never))
                            .foregroundStyle(metrics.status < 400 ? .green : .red)
                            .monospacedDigit()
                    }
                    LabeledContent("Timing", value: Self.timing(metrics))
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(viewModel.reply.isEmpty ? "Waiting for the model…" : "Streaming…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if let notice = viewModel.notice {
                    Label(notice, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
                if !viewModel.reply.isEmpty {
                    Text(viewModel.reply)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("Copy Reply", systemImage: "doc.on.doc") { UIPasteboard.general.string = viewModel.reply }
                        }
                }
            }
            if !viewModel.rawResponse.isEmpty {
                Section {
                    DisclosureGroup("Raw response") {
                        code(viewModel.rawResponse)
                    }
                    DisclosureGroup("Request sent") {
                        code(viewModel.requestBodyText)
                    }
                }
            }
        } else {
            Section {
                ContentUnavailableView(
                    "No response yet",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    description: Text("Write a message and tap Run. The reply, its raw JSON and timing show up here.")
                )
            }
        }
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
            }
    }

    // MARK: Helpers

    /// Form ↔ JSON. Going to JSON starts from what the form would send;
    /// coming back keeps the form as it was.
    private var editor: Binding<Bool> {
        Binding { viewModel.isRaw } set: { raw in
            if raw { viewModel.editAsJSON() } else { viewModel.isRaw = false }
        }
    }

    private var tokenFooter: String {
        let tokens = TokenEstimate.tokens(in: viewModel.promptText)
        return TokenEstimate.label(tokens: tokens, window: contextWindow(viewModel.model))
            + " in the prompt (an estimate: about four characters each)."
    }

    static func timing(_ metrics: PlaygroundViewModel.Metrics) -> String {
        var parts = ["\(Format.rate(Double(metrics.durationMs) / 1000)) s"]
        if let first = metrics.firstTokenMs { parts.append("first token \(first) ms") }
        if let tokens = metrics.tokens { parts.append("\(tokens) tokens") }
        if let speed = metrics.tokensPerSecond { parts.append("\(Format.rate(speed)) tok/s") }
        return parts.joined(separator: " · ")
    }

    private func copy(_ snippet: PlaygroundViewModel.Snippet) {
        UIPasteboard.general.string = viewModel.code(snippet)
        copied = snippet
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = nil
        }
    }
}

#Preview {
    PlaygroundView(
        viewModel: ChatListViewModel.preview.playground,
        makeSelector: ChatListViewModel.preview.makeModelSelector,
        contextWindow: { _ in 8192 }
    )
}
