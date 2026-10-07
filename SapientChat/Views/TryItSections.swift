import SwiftUI
import UIKit

/// The Server screen's Try It: pick where to call and which model the
/// commands name, then copy any command. Picking a model only fills in the
/// commands; nothing loads.
struct TryItSections: View {
    let viewModel: ServerViewModel
    @State private var endpoint = ""
    @State private var model = PhoneModel.defaultAlias

    var body: some View {
        Section {
            Picker("Endpoint", selection: $endpoint) {
                ForEach(viewModel.endpoints, id: \.url) { endpoint in
                    Text(endpoint.label).tag(endpoint.url)
                }
            }
            Picker("Model", selection: $model) {
                ForEach(viewModel.models) { model in
                    Text(model.displayName).tag(model.alias)
                }
            }
        } header: {
            Text("Try it")
        } footer: {
            Text("Commands use this endpoint and model\(viewModel.apiKey.isEmpty ? "" : ", and your API key"). Run them in Terminal on a device that can reach this one.")
        }
        ForEach(ServeCommand.Group.allCases, id: \.self) { group in
            Section(group.rawValue) {
                ForEach(commands.filter { $0.group == group }) { command in
                    CommandRow(command: command)
                }
            }
        }
        .onAppear(perform: pickEndpoint)
        .onChange(of: viewModel.endpoints.map(\.url)) { pickEndpoint() }
    }

    private var commands: [ServeCommand] {
        ServeCommands.all(base: endpoint, apiKey: viewModel.apiKey, model: model)
    }

    /// Prefers a network address (what another device needs), else this device.
    private func pickEndpoint() {
        let urls = viewModel.endpoints.map(\.url)
        if !urls.contains(endpoint) { endpoint = urls.last ?? "" }
    }
}

private struct CommandRow: View {
    let command: ServeCommand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(command.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Copy", systemImage: "doc.on.doc", action: copy)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Text(command.command)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Command", systemImage: "doc.on.doc", action: copy)
        }
    }

    private func copy() {
        UIPasteboard.general.string = command.command
    }
}
