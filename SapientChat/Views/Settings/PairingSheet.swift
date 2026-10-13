// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import CoreImage.CIFilterBuiltins
import SwiftUI

/// What a client needs to reach this device's API server, as the JSON a
/// pairing QR code carries: `{"url", "base_url", "api_key"?}`. `base_url`
/// ends in `/v1`, as OpenAI SDKs expect; `url` is what SapientKit takes.
nonisolated struct ServerPairing: Equatable, Sendable, Codable {
    let url: String
    let baseUrl: String
    var apiKey: String?

    init(url: String, apiKey: String?) {
        self.url = url
        baseUrl = url + "/v1"
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case baseUrl = "base_url"
        case apiKey = "api_key"
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// A QR code of `text`, scaled up without blur; nil if it can't be made.
    static func qrCode(for text: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let image = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: image)
    }
}

/// A QR code another device scans to connect to this server, so nobody
/// types an IP address or an API key.
struct PairingSheet: View {
    let endpoints: [(label: String, url: String)]
    let apiKey: String
    @State private var selected = ""
    @State private var includesKey = true
    @Environment(\.dismiss) private var dismiss

    private var pairing: ServerPairing {
        ServerPairing(url: selected, apiKey: includesKey ? apiKey : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image = ServerPairing.qrCode(for: pairing.json) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .padding(12)
                            .background(.white, in: .rect(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .accessibilityLabel("Pairing QR code for \(selected)")
                    }
                } footer: {
                    Text("Scan with the other device. The code holds this server's address as JSON: \"url\", \"base_url\" (ending in /v1, for OpenAI SDKs)\(pairing.apiKey == nil ? "" : " and \"api_key\"").")
                }
                Section {
                    if endpoints.count > 1 {
                        Picker("Address", selection: $selected) {
                            ForEach(endpoints, id: \.url) { endpoint in
                                Text("\(endpoint.label) · \(endpoint.url)").tag(endpoint.url)
                            }
                        }
                    }
                    LabeledContent("Base URL") {
                        Text(pairing.baseUrl)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    if !apiKey.isEmpty {
                        Toggle("Include API key", isOn: $includesKey)
                    }
                    Button("Copy as JSON", systemImage: "doc.on.doc") { UIPasteboard.general.string = pairing.json }
                } footer: {
                    Text(apiKey.isEmpty
                        ? "No API key is set, so anyone on this network who has the address can use the server."
                        : "With the key included, anyone who sees this code can use the server. Show it only to devices you trust.")
                }
            }
            .navigationTitle("Pair a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // The address other devices use, not this device's own.
                if selected.isEmpty { selected = endpoints.last?.url ?? "" }
            }
        }
    }
}
