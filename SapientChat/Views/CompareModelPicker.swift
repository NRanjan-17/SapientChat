import SwiftUI

/// A menu picker over the catalog for one side of a comparison.
struct CompareModelPicker: View {
    let title: String
    let models: [PhoneModel]
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(models) { model in
                Text("\(model.displayName) · ≈\(Format.bytes(model.estimatedMemoryBytes))")
                    .tag(model.alias)
            }
        }
    }
}
