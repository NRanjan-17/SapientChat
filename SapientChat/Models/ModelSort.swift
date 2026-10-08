// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// How the Models tab orders models within each section.
nonisolated enum ModelSort: String, CaseIterable, Sendable {
    case smallestFirst
    case largestFirst

    var title: String {
        switch self {
        case .smallestFirst: "Smallest First"
        case .largestFirst: "Largest First"
        }
    }

    /// `models` ordered by the memory each needs; ties keep catalog order.
    func sorted<Item>(_ items: [Item], by model: (Item) -> PhoneModel) -> [Item] {
        items.enumerated().sorted { a, b in
            let (sizeA, sizeB) = (model(a.element).estimatedMemoryBytes, model(b.element).estimatedMemoryBytes)
            if sizeA == sizeB { return a.offset < b.offset }
            return self == .smallestFirst ? sizeA < sizeB : sizeA > sizeB
        }
        .map(\.element)
    }
}
