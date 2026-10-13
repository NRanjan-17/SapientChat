// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Run a saved set of prompts against up to three models and read every
/// answer side by side with its speed.
struct PromptSetsView: View {
    @Bindable var viewModel: PromptSetsViewModel
    let makeSelector: (String, @escaping (String) -> Void) -> ModelSelectorViewModel
    /// Single Model / Compare / Prompt Sets, first in the setup column.
    var modeSwitch: BenchmarkModeSwitch?
    @State private var editing: PromptSet?
    @State private var isConfirmingDelete = false

    var body: some View {
        SetupResultsLayout {
            if let modeSwitch { modeSwitch }
            setSection
            modelSection
            runSection
        } results: {
            results
        }
        .sheet(item: $editing) { set in
            PromptSetEditor(set: set, onSave: viewModel.save)
        }
        .alert("Delete “\(viewModel.selected?.name ?? "")”?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let set = viewModel.selected { viewModel.delete(set) }
            }
        } message: {
            Text("Its prompts and saved runs are removed from this device.")
        }
        .problemAlert($viewModel.alert)
        .toolbar {
            if let set = viewModel.selected, !set.runs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: set.exportJSON(), preview: SharePreview("\(set.name) results")) {
                        Label("Share Results", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: Setup

    private var setSection: some View {
        Section {
            Picker("Prompt set", selection: $viewModel.selectedID) {
                ForEach(viewModel.sets) { set in
                    Text(set.name).tag(PromptSet.ID?.some(set.id))
                }
            }
            if let set = viewModel.selected {
                Button("Edit Prompts (\(set.usablePrompts.count))", systemImage: "pencil") { editing = set }
            }
            Button("New Set", systemImage: "plus") { editing = viewModel.newSet() }
            if viewModel.sets.count > 1 {
                Button("Delete Set", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
        } footer: {
            Text("Every prompt is sent to every model, as a new chat each time.")
        }
        .disabled(viewModel.isRunning)
    }

    private var modelSection: some View {
        Section {
            ForEach(Array(viewModel.models.enumerated()), id: \.offset) { index, alias in
                ModelPickerField(
                    title: viewModel.models.count > 1 ? "Model \(index + 1)" : "Model",
                    selection: alias, makeSelector: makeSelector
                ) { viewModel.setModel($0, at: index) }
                    .swipeActions {
                        if viewModel.models.count > 1 {
                            Button("Remove", systemImage: "minus.circle", role: .destructive) { viewModel.removeModel(at: index) }
                        }
                    }
            }
            if viewModel.canAddModel {
                Button("Add Model", systemImage: "plus", action: viewModel.addModel)
            }
            Picker("Tokens per answer", selection: $viewModel.maxTokens) {
                ForEach(PromptSetsViewModel.maxTokenChoices, id: \.self) { choice in
                    Text(choice, format: .number).tag(choice)
                }
            }
        } footer: {
            Text("Up to \(PromptSetsViewModel.maxModels) models, one after the other. Swipe a model to remove it. Answers use each model's own temperature (Precise repeats exactly).")
        }
        .disabled(viewModel.isRunning)
    }

    private var runSection: some View {
        Section {
            if let progress = viewModel.progress {
                ProgressView(value: progress.fraction) {
                    Text(progress.label)
                } currentValueLabel: {
                    Text("\(progress.done) of \(progress.total) answers")
                }
                Button("Cancel", role: .cancel, action: viewModel.cancel)
            } else {
                Button("Run Prompt Set", systemImage: "play.fill", action: viewModel.run)
                    .disabled(!viewModel.canRun)
            }
        }
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        if let set = viewModel.selected, let run = set.runs.first {
            Section {
                LabeledContent("Ran", value: run.date.formatted(date: .abbreviated, time: .shortened))
                ForEach(run.models, id: \.self) { alias in
                    LabeledContent(viewModel.displayName(of: alias), value: Self.summary(of: alias, in: run))
                }
            } header: {
                Text(run.cancelled ? "Latest run (stopped early)" : "Latest run")
            } footer: {
                if let before = set.runs.dropFirst().first {
                    Text(Self.changes(from: before, to: run))
                }
            }
            ForEach(Array(set.usablePrompts.enumerated()), id: \.offset) { index, prompt in
                let answers = run.answers(to: prompt)
                if !answers.isEmpty {
                    Section {
                        ForEach(answers) { answer in
                            PromptAnswerRow(answer: answer, name: viewModel.displayName(of: answer.model))
                        }
                    } header: {
                        Text("\(index + 1). \(prompt)")
                            .textCase(nil)
                    }
                }
            }
        } else {
            Section {
                ContentUnavailableView(
                    "No runs yet",
                    systemImage: "checklist",
                    description: Text("Run the set to see every model's answer to every prompt, with its speed.")
                )
            }
        }
    }

    /// "4 answers · 31.2 tok/s", or how many failed.
    static func summary(of alias: String, in run: PromptSet.Run) -> String {
        let answers = run.answers.filter { $0.model == alias }
        let failed = answers.count { $0.error != nil }
        let speeds = answers.compactMap(\.tokensPerSecond)
        var parts = ["\(answers.count - failed) answers"]
        if failed > 0 { parts.append("\(failed) failed") }
        if !speeds.isEmpty { parts.append("\(Format.rate(speeds.reduce(0, +) / Double(speeds.count))) tok/s") }
        return parts.joined(separator: " · ")
    }

    /// How many answers differ from the run before, for the same prompt and model.
    static func changes(from before: PromptSet.Run, to run: PromptSet.Run) -> String {
        var compared = 0
        var changed = 0
        for answer in run.answers {
            guard let old = before.answers.first(where: { $0.prompt == answer.prompt && $0.model == answer.model }) else { continue }
            compared += 1
            if old.reply != answer.reply { changed += 1 }
        }
        guard compared > 0 else { return "Nothing in the run before this one to compare with." }
        return changed == 0
            ? "All \(compared) answers match the run before this one."
            : "\(changed) of \(compared) answers changed since the run before this one."
    }
}

/// One model's answer: its name, speed and text.
struct PromptAnswerRow: View {
    let answer: PromptSet.Answer
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(stats)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let error = answer.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else {
                Text(answer.reply.isEmpty ? "(empty)" : answer.reply)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Answer", systemImage: "doc.on.doc") { UIPasteboard.general.string = answer.reply }
        }
    }

    private var stats: String {
        var parts = ["\(answer.tokens) tokens"]
        if let speed = answer.tokensPerSecond { parts.append("\(Format.rate(speed)) tok/s") }
        if let first = answer.firstTokenMs { parts.append("\(first) ms") }
        return parts.joined(separator: " · ")
    }
}

/// Edits a set's name, system prompt and prompts.
struct PromptSetEditor: View {
    let onSave: (PromptSet) -> Void
    @State private var set: PromptSet
    @Environment(\.dismiss) private var dismiss

    init(set: PromptSet, onSave: @escaping (PromptSet) -> Void) {
        _set = State(initialValue: set)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $set.name)
                }
                Section {
                    TextField("Optional instructions sent before each prompt", text: $set.systemPrompt, axis: .vertical)
                        .lineLimit(1...5)
                } header: {
                    Text("System prompt")
                }
                Section {
                    ForEach(set.prompts.indices, id: \.self) { index in
                        TextField("Prompt \(index + 1)", text: $set.prompts[index], axis: .vertical)
                            .lineLimit(1...8)
                    }
                    .onDelete { set.prompts.remove(atOffsets: $0) }
                    .onMove { set.prompts.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add Prompt", systemImage: "plus") { set.prompts.append("") }
                } header: {
                    Text("Prompts")
                } footer: {
                    Text("Swipe a prompt to delete it. Empty prompts are skipped.")
                }
            }
            .navigationTitle("Edit Prompt Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(set)
                        dismiss()
                    }
                }
            }
        }
    }
}
