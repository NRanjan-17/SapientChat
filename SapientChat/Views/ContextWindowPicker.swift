import SwiftUI

/// Picks how many tokens a model keeps in view: its default, or 1K–8K.
struct ContextWindowPicker: View {
    let model: PhoneModel
    let isLoaded: Bool
    @Binding var tokens: Int?

    var body: some View {
        Section {
            Picker("Context window", selection: $tokens) {
                Text("Default").tag(Int?.none)
                ForEach(ContextWindowStore.choices, id: \.self) { choice in
                    Text("\(choice.formatted()) tokens").tag(Int?.some(choice))
                }
            }
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "How much of the conversation \(model.displayName) can see at once. A bigger window remembers more but uses more memory. Default is 3,072 tokens for models above 1.5B, 8,192 otherwise."
        if isLoaded {
            text += " Changing it reloads the model."
        }
        return text
    }
}

/// The Models tab's context window screen for one model.
struct ContextWindowSheet: View {
    let model: PhoneModel
    let isLoaded: Bool
    let onSave: (Int?) -> Void
    @State private var tokens: Int?
    @Environment(\.dismiss) private var dismiss

    init(model: PhoneModel, current: Int?, isLoaded: Bool, onSave: @escaping (Int?) -> Void) {
        self.model = model
        self.isLoaded = isLoaded
        self.onSave = onSave
        _tokens = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                ContextWindowPicker(model: model, isLoaded: isLoaded, tokens: $tokens)
            }
            .navigationTitle("Context Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        onSave(tokens)
        dismiss()
    }

    private func close() {
        dismiss()
    }
}
