import Foundation

/// A chat model the app offers.
nonisolated struct PhoneModel: Identifiable, Hashable, Sendable {
    let alias: String
    /// Hugging Face repository the files are downloaded from.
    let repoId: String
    /// Catalog size string for display, e.g. "135M Q4_K_M".
    let params: String
    /// Parameter count in billions, parsed from `params`.
    let billions: Double

    var id: String { alias }

    /// The alias without the catalog's `openhorizon/` prefix, for display.
    var displayName: String {
        alias.split(separator: "/").last.map(String.init) ?? alias
    }

    /// Storage format shown to the user.
    var format: String {
        if params.contains("Q4") {
            "4-bit"
        } else if params.contains("Q8") {
            "8-bit"
        } else {
            "Full precision"
        }
    }

    /// ~100 MB: the fastest way to check the whole pipeline works.
    static let defaultAlias = "openhorizon/smollm2-135m-q4"

    /// Rough memory the loaded model needs, in bytes: weights as they sit in
    /// memory plus ~0.6 GB for the KV cache and runtime. Weights per
    /// parameter: Q4_K_M GGUF ≈ 0.6 bytes, Q8_0 ≈ 1.07, and full-precision
    /// checkpoints ≈ 1.3 (converted to Q8_0 at load, with the embedding
    /// table kept at full precision). An estimate for a go/no-go check, not
    /// a measurement: run the benchmark for the real peak.
    var estimatedMemoryBytes: UInt64 {
        let bytesPerParam: Double = if params.contains("Q4") {
            0.6
        } else if params.contains("Q8") {
            1.07
        } else {
            1.3
        }
        let overhead = 0.6e9
        return UInt64(billions * 1e9 * bytesPerParam + overhead)
    }

    /// Why this model won't fit, or nil if it should. `availableBytes` is
    /// what the app may still allocate (nil = no known limit, e.g. the
    /// simulator); `reclaimableBytes` is memory that loading frees first
    /// (the model being replaced).
    func fitProblem(availableBytes: UInt64?, reclaimableBytes: UInt64 = 0) -> String? {
        guard let availableBytes else { return nil }
        let headroom = availableBytes + reclaimableBytes
        guard estimatedMemoryBytes > headroom else { return nil }
        let need = Int64(clamping: estimatedMemoryBytes).formatted(.byteCount(style: .memory))
        let have = Int64(clamping: headroom).formatted(.byteCount(style: .memory))
        return "\(alias) needs about \(need), but iOS lets this app use about \(have) more. "
            + "Pick a smaller model or its Q4 build."
    }

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
