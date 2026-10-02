import SwiftUI

/// Menu for choosing the chat model. A new choice loads on the next message.
struct ModelPickerView: View {
    let models: [PhoneModel]
    @Binding var selection: String

    var body: some View {
        Picker("Model", systemImage: "cpu", selection: $selection) {
            ForEach(models) { model in
                Text("\(model.alias) (\(model.params))").tag(model.alias)
            }
        }
        .pickerStyle(.menu)
    }
}

#Preview {
    @Previewable @State var selection = PhoneModel.defaultAlias
    ModelPickerView(models: PhoneModel.samples, selection: $selection)
}
