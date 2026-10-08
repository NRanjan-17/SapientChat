// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import SwiftData
import Testing
@testable import SapientChat

@MainActor
struct BenchmarkModelPickerTests {
    private func makeList() throws -> ChatListViewModel {
        let container = try makeContainer()
        return ChatListViewModel(
            services: makeServices(chat: ControlledChatService()),
            store: SwiftDataConversationStore(context: container.mainContext)
        )
    }

    @Test func pickingAModelSetsTheBenchmarksModel() async throws {
        let list = try makeList()
        let picker = list.makeModelSelector(selected: list.benchmark.model) { list.benchmark.model = $0 }
        await picker.refresh()
        #expect(picker.canSelect)
        let big = try #require(picker.notDownloadedRows.first { $0.model == TestModels.big } ?? picker.downloadedRows.first { $0.model == TestModels.big })
        picker.select(big)
        #expect(list.benchmark.model == TestModels.big.alias)
    }

    @Test func compareSwapsInsteadOfPickingTheSameModelTwice() throws {
        let compare = try makeList().compare
        compare.modelA = TestModels.small.alias
        compare.modelB = TestModels.big.alias

        compare.selectModelA(TestModels.big.alias)
        #expect(compare.modelA == TestModels.big.alias)
        #expect(compare.modelB == TestModels.small.alias)

        compare.selectModelB(TestModels.big.alias)
        #expect(compare.modelA == TestModels.small.alias)
        #expect(compare.modelB == TestModels.big.alias)
        #expect(compare.modelA != compare.modelB)
    }
}
