// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// The Terms of Service. Shown over the app at first launch, where it must
/// be accepted to go on; and from Settings → About, to read again.
struct TermsOfServiceView: View {
    /// Set at first launch: shows Agree and Continue, and can't be dismissed
    /// any other way. Nil when it's opened to read.
    var onAgree: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Text(markdown(TermsOfService.introduction))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(TermsOfService.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.headline)
                            Text(markdown(section.body))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("OpenHorizon Labs Pvt Ltd · [openhorizon.so](\(TermsOfService.companyURL))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Last updated \(TermsOfService.lastUpdated)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                if let onAgree {
                    VStack(spacing: 8) {
                        Button(action: onAgree) {
                            Text("Agree and Continue")
                                .font(.headline)
                                .frame(maxWidth: 420)
                                .frame(minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        Text("By continuing you accept these terms.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                }
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onAgree == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        // First launch: the only way on is to agree.
        .interactiveDismissDisabled(onAgree != nil)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(.logoSapient)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(11)
                .frame(width: 54, height: 54)
                .background(.tint, in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sapient Studio")
                    .font(.title2.bold())
                Text("Terms of Service and Notice")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The text with its Markdown links and emphasis; plain if it won't parse.
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

#Preview("First launch") {
    TermsOfServiceView(onAgree: {})
}

#Preview("From Settings") {
    TermsOfServiceView()
}
