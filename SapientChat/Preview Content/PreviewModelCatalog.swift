// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// `ModelCatalogService` for SwiftUI previews.
nonisolated struct PreviewModelCatalog: ModelCatalogService {
    func chatModels() -> [PhoneModel] {
        PhoneModel.samples
    }
}
