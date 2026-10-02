import Sapient

/// `ModelCatalogService` backed by SAPIENT's built-in model catalog.
nonisolated struct SapientModelCatalog: ModelCatalogService {
    /// Largest model offered, in billions of parameters.
    var maxBillions = 1.7

    /// Ungated chat models up to `maxBillions`, smallest first.
    func chatModels() -> [PhoneModel] {
        listModels()
            .filter { $0.category == "chat" && !$0.gated }
            .compactMap { entry in
                guard let billions = PhoneModel.billions(fromParams: entry.params),
                      billions <= maxBillions
                else { return nil }
                return PhoneModel(alias: entry.alias, repoId: entry.repoId, params: entry.params, billions: billions)
            }
            .sorted { $0.billions < $1.billions }
    }
}
