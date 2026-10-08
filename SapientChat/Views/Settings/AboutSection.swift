// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

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
                Text("Sapient Chat © 2026 Nalinish Ranjan, licensed under the GNU Affero General Public License v3.0 only, or a commercial license from its author. It comes with no warranty.")
                Text("The SAPIENT engine © 2026 OpenHorizon Labs Pvt Ltd, licensed under AGPL-3.0-only or a commercial license from OpenHorizon Labs. \"SAPIENT\" and its logo are their trademarks.")
            } header: {
                Text("Licenses")
            } footer: {
                Text("Full texts: LICENSE, NOTICE and COMMERCIAL-LICENSE.md in the source repository.")
            }
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
