/// Lists the models the app offers.
nonisolated protocol ModelCatalogService: Sendable {
    func chatModels() -> [PhoneModel]
}
