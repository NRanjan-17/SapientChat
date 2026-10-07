import SwiftUI

/// Versions of the app, the engine and the device it runs on.
struct AboutSection: View {
    private let device = DeviceInfo.current()

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        Section("About") {
            LabeledContent("App", value: appVersion)
            LabeledContent("SAPIENT engine", value: SapientVersion.current)
            LabeledContent("Device", value: device.model)
            LabeledContent("System", value: device.system)
            NavigationLink("Acknowledgements") {
                AcknowledgementsView()
            }
        }
    }
}

/// Third-party work shipped in the app, with its licence.
struct AcknowledgementsView: View {
    var body: some View {
        Form {
            Section {
                Text(Self.lobeHubLicense)
                    .font(.footnote)
                    .textSelection(.enabled)
            } header: {
                Text("LobeHub Icons")
            } footer: {
                Text("Model maker logos. The logos are trademarks of their owners and identify which company made each model.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let lobeHubLicense = """
        MIT License

        Copyright (c) 2023 LobeHub

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
}
