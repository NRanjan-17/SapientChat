// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Lists the models the app offers.
nonisolated protocol ModelCatalogService: Sendable {
    func chatModels() -> [PhoneModel]
}
