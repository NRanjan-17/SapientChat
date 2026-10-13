// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// The notice a person accepts before using the app: who it belongs to,
/// what happens to their data, and that the models come from third parties
/// with no guarantee. Raise `version` when the text changes in substance,
/// and everyone is asked again.
nonisolated enum TermsOfService {
    struct Section: Identifiable, Equatable, Sendable {
        let title: String
        /// Markdown, so a link can be tapped.
        let body: String

        var id: String { title }
    }

    static let version = 1
    static let acceptedVersionKey = "terms.acceptedVersion"
    static let companyURL = "https://openhorizon.so"
    static let lastUpdated = "13 October 2026"

    static let introduction = "Please read this notice carefully. By selecting **Agree and Continue** you confirm that you have read, understood and accept these terms. If you do not agree, do not use the application."

    static let sections: [Section] = [
        Section(
            title: "1. Ownership",
            body: "Sapient Studio (the \u{201C}Application\u{201D}) is the property of OpenHorizon Labs Pvt Ltd (\u{201C}OpenHorizon Labs\u{201D}, \u{201C}we\u{201D}, \u{201C}us\u{201D}). Further information about the company is available at [openhorizon.so](\(companyURL))."
        ),
        Section(
            title: "2. Your Data",
            body: "OpenHorizon Labs does not collect, store, transmit, sell or share any personal data or any content you create in the Application. Your prompts, replies, conversations, settings and request logs are processed and kept on your device only. The Application has no user accounts, analytics or advertising."
        ),
        Section(
            title: "3. Third-Party Models",
            body: "The language models offered in the Application are created and published by third parties and are downloaded to your device directly from Hugging Face. OpenHorizon Labs does not host, alter, endorse or control these models. Each model is subject to the licence and terms set by its publisher, which you are responsible for reviewing and complying with. Downloading a model connects your device to Hugging Face, and that connection is governed by Hugging Face\u{2019}s own terms and privacy policy."
        ),
        Section(
            title: "4. No Warranty",
            body: "The Application and every model available through it are provided \u{201C}as is\u{201D} and \u{201C}as available\u{201D}, without warranty of any kind, whether express or implied. OpenHorizon Labs gives no guarantee as to the accuracy, reliability, safety, lawfulness, performance or fitness for any purpose of any model or of any output a model produces. Output may be incorrect, incomplete, misleading or offensive, and is not professional advice. You are solely responsible for how you use the Application and for any reliance you place on its output."
        ),
        Section(
            title: "5. Limitation of Liability",
            body: "To the fullest extent permitted by applicable law, OpenHorizon Labs and its contributors shall not be liable for any direct, indirect, incidental, special or consequential loss or damage arising out of or in connection with your use of, or inability to use, the Application or any model."
        ),
        Section(
            title: "6. Acknowledgements",
            body: "OpenHorizon Labs gratefully acknowledges the contributors Nalinish Ranjan and Saidev Dhal for developing Sapient Studio. The licences that apply to the software and to third-party material are set out under Settings \u{2192} About \u{2192} Acknowledgements."
        ),
        Section(
            title: "7. Changes to These Terms",
            body: "We may revise these terms from time to time. If they change in substance, you will be asked to review and accept them again before continuing to use the Application."
        ),
    ]

    /// Whether the current version has been accepted on this device.
    static func isAccepted(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: acceptedVersionKey) >= version
    }

    static func accept(_ defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: acceptedVersionKey)
    }
}
