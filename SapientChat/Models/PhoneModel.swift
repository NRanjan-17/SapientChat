// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

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

    /// Size of the files to download, in bytes, for "about 105 MB" before a
    /// download starts (the download itself reports the real total). The
    /// measured size of the repository's weights file where known; else an
    /// estimate from the parameter count, within about 25% of the repos
    /// measured: Q4_K_M ≈ 0.8 bytes per parameter, Q8_0 ≈ 1.2, and a
    /// full-precision checkpoint (16-bit safetensors) ≈ 2.
    var estimatedDownloadBytes: UInt64 {
        let megabytes: [String: Double]
        let bytesPerParam: Double
        if params.contains("Q4") {
            megabytes = Self.q4Megabytes
            bytesPerParam = 0.8
        } else if params.contains("Q8") {
            megabytes = Self.q8Megabytes
            bytesPerParam = 1.2
        } else {
            megabytes = Self.fullMegabytes
            bytesPerParam = 2
        }
        if let known = megabytes[repoId] { return UInt64(known * 1e6) }
        return UInt64(billions * 1e9 * bytesPerParam)
    }

    /// "105 MB" for a measured size, "About 540 MB" for an estimate.
    var downloadSizeText: String {
        let size = Format.compactBytes(estimatedDownloadBytes)
        let measured: [String: Double] = if params.contains("Q4") {
            Self.q4Megabytes
        } else if params.contains("Q8") {
            Self.q8Megabytes
        } else {
            Self.fullMegabytes
        }
        return measured[repoId] == nil ? "About \(size)" : size
    }

    /// Weights file sizes on Hugging Face, in MB, by repository (October 2026).
    private static let q4Megabytes: [String: Double] = [
        "unsloth/SmolLM2-135M-Instruct-GGUF": 105,
        "Qwen/Qwen2.5-0.5B-Instruct-GGUF": 491,
        "unsloth/Qwen2.5-Coder-0.5B-Instruct-GGUF": 398,
        "unsloth/Llama-3.2-1B-Instruct-GGUF": 808,
        "Qwen/Qwen2.5-1.5B-Instruct-GGUF": 1117,
        "unsloth/Qwen2.5-Coder-1.5B-Instruct-GGUF": 986,
        "unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF": 1117,
        "HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF": 1056,
    ]
    private static let q8Megabytes: [String: Double] = [
        "unsloth/SmolLM2-135M-Instruct-GGUF": 145,
        "HuggingFaceTB/SmolLM2-360M-Instruct-GGUF": 386,
        "Qwen/Qwen2.5-0.5B-Instruct-GGUF": 676,
        "unsloth/Qwen2.5-Coder-0.5B-Instruct-GGUF": 531,
        "unsloth/Llama-3.2-1B-Instruct-GGUF": 1321,
        "Qwen/Qwen2.5-1.5B-Instruct-GGUF": 1895,
        "unsloth/Qwen2.5-Coder-1.5B-Instruct-GGUF": 1647,
        "unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF": 1895,
    ]
    private static let fullMegabytes: [String: Double] = [
        "HuggingFaceTB/SmolLM2-135M-Instruct": 269,
        "unsloth/gemma-3-270m-it": 569,
        "google/gemma-3-270m-it": 569,
        "unsloth/gemma-3-1b-it": 2033,
        "microsoft/phi-1": 2837,
        "microsoft/phi-1_5": 2837,
        "HuggingFaceTB/SmolLM2-360M-Instruct": 724,
        "Qwen/Qwen2.5-0.5B-Instruct": 988,
        "unsloth/Llama-3.2-1B-Instruct": 2472,
        "TinyLlama/TinyLlama-1.1B-Chat-v1.0": 2200,
        "Qwen/Qwen2.5-1.5B-Instruct": 3087,
        "HuggingFaceTB/SmolLM2-1.7B-Instruct": 3423,
    ]

    /// A 4-bit or 8-bit GGUF, which iOS memory-maps: the CPU can read its
    /// weights from the file, so CPU + GPU doesn't need a second copy in
    /// memory. Full-precision (safetensors) models load into memory.
    var isMemoryMapped: Bool {
        params.contains("Q4") || params.contains("Q8")
    }

    /// This model as the memory check should see it on `backend`: CPU + GPU
    /// keeps a second copy of a model that isn't memory-mapped.
    func forPlanning(backend: String?) -> PhoneModel {
        guard backend == "hybrid", !isMemoryMapped else { return self }
        return PhoneModel(alias: alias, repoId: repoId, params: params, billions: billions * 2)
    }

    /// Why this model won't fit, or nil if it should. `availableBytes` is
    /// what the app may still allocate (nil = no known limit, e.g. the
    /// simulator); `reclaimableBytes` is memory that loading frees first
    /// (the model being replaced).
    /// `requiredBytes` overrides the estimate (e.g. what it really took).
    func fitProblem(availableBytes: UInt64?, reclaimableBytes: UInt64 = 0, requiredBytes: UInt64? = nil) -> String? {
        guard let availableBytes else { return nil }
        let required = requiredBytes ?? estimatedMemoryBytes
        let headroom = availableBytes > .max - reclaimableBytes ? .max : availableBytes + reclaimableBytes
        guard required > headroom else { return nil }
        let need = Int64(clamping: required).formatted(.byteCount(style: .memory))
        let have = Int64(clamping: headroom).formatted(.byteCount(style: .memory))
        return "\(displayName) needs about \(need), but iOS lets Sapient use only about \(have) more, even after releasing idle models. "
            + "Pick a smaller model or its 4-bit (Q4) version, or close other apps and tap Try Again."
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
