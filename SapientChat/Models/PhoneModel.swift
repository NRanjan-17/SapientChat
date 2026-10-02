/// A chat model small enough to run on a phone.
nonisolated struct PhoneModel: Identifiable, Hashable, Sendable {
    let alias: String
    /// Catalog size string for display, e.g. "135M Q4_K_M".
    let params: String
    /// Parameter count in billions, parsed from `params`.
    let billions: Double

    var id: String { alias }

    /// ~100 MB: the fastest way to check the whole pipeline works.
    static let defaultAlias = "smollm2-135m-q4"

    /// "135M Q4_K_M" → 0.135, "1.5B" → 1.5. Returns nil for anything else,
    /// including mixture-of-experts sizes like "47B-A13B".
    static func billions(fromParams params: String) -> Double? {
        guard let size = params.split(separator: " ").first, let unit = size.last,
              let value = Double(size.dropLast())
        else { return nil }
        return switch unit {
        case "M": value / 1000
        case "B": value
        default: nil
        }
    }
}
