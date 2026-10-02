/// `ModelCatalogService` for SwiftUI previews.
nonisolated struct PreviewModelCatalog: ModelCatalogService {
    func chatModels() -> [PhoneModel] {
        PhoneModel.samples
    }
}
