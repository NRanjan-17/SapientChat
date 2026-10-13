// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import ActivityKit
import SwiftUI
import WidgetKit

/// SAPIENT's Live Activity: the model, what it's doing and its live stats,
/// in the Dynamic Island and on the Lock Screen. SAPIENT blue (the app
/// icon's) is the Island's colour: serving, generating, downloading and
/// done all use it. Loading is violet, benchmarks orange and failures red,
/// so those stand apart at a glance.
struct SapientLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SapientActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding(16)
                // Clear, so the Lock Screen's Liquid Glass shows through.
                .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            let state = context.state
            let look = PhaseLook(state: state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Header(attributes: context.attributes, look: look)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HeroValue(state: state, look: look)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusLine(state: state, look: look)
                        if let progress = state.progress, !state.isOver {
                            ProgressBar(value: progress, look: look)
                        }
                        StatsRow(state: state)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                SapientMark(look: look)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                CompactValue(state: state, look: look)
            } minimal: {
                MinimalMark(state: state, look: look)
            }
            .keylineTint(look.tint)
        }
    }
}

// MARK: Look

/// The colours and symbol for what the activity is doing.
private struct PhaseLook {
    let tint: Color
    let secondTint: Color
    let symbol: String
    let label: String

    init(state: SapientActivityAttributes.ContentState, isStale: Bool = false) {
        label = isStale && !state.isOver && state.phase != .paused ? "Not updating" : state.phase.label
        if isStale && !state.isOver && state.phase != .paused {
            (tint, secondTint, symbol) = (.gray, .gray, "pause.circle.fill")
            return
        }
        switch state.phase {
        case .preparing: (tint, secondTint, symbol) = (Self.brand, Self.brandLight, "hourglass")
        case .downloading: (tint, secondTint, symbol) = (Self.brand, Self.brandLight, "arrow.down.circle.fill")
        case .loading: (tint, secondTint, symbol) = (.indigo, .purple, "memorychip.fill")
        case .generating: (tint, secondTint, symbol) = (Self.brand, .cyan, "sparkles")
        case .benchmarking: (tint, secondTint, symbol) = (.orange, .yellow, "gauge.with.dots.needle.67percent")
        case .serving: (tint, secondTint, symbol) = (Self.brand, Self.brandLight, "antenna.radiowaves.left.and.right")
        case .paused: (tint, secondTint, symbol) = (.gray, .gray, "pause.circle.fill")
        case .finished: (tint, secondTint, symbol) = (Self.brand, Self.brandLight, "checkmark.circle.fill")
        case .failed: (tint, secondTint, symbol) = (.red, .orange, "exclamationmark.triangle.fill")
        }
    }

    /// SAPIENT blue as the app icon shows it on dark (#2A7DFF), which is
    /// what the Island's black needs, and a lighter step for gradients.
    static let brand = Color(red: 0x2A / 255, green: 0x7D / 255, blue: 1)
    static let brandLight = Color(red: 0x6A / 255, green: 0xB0 / 255, blue: 1)

    var gradient: LinearGradient {
        LinearGradient(colors: [tint, secondTint], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The SAPIENT mark in the phase's colour.
private struct SapientMark: View {
    let look: PhaseLook

    var body: some View {
        Image("SapientMark")
            .resizable()
            .scaledToFit()
            .foregroundStyle(look.gradient)
    }
}

// MARK: Pieces

/// The mark on a tinted tile, the model and who asked.
private struct Header: View {
    let attributes: SapientActivityAttributes
    let look: PhaseLook

    /// The server's activity carries its address where others carry a
    /// model. An address is long, so it goes on the small line, where it
    /// fits whole, under the name.
    private var isServer: Bool { attributes.title == "API server" }
    private var primary: String { isServer ? "Sapient" : attributes.model }
    private var secondary: String { isServer ? attributes.model : attributes.title }

    var body: some View {
        HStack(spacing: 8) {
            Image("SapientMark")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(7)
                .frame(width: 34, height: 34)
                .background(look.gradient, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(primary)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(secondary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// The one number that matters right now, large: speed while generating,
/// percent while downloading, requests while serving, else the time taken.
private struct HeroValue: View {
    let state: SapientActivityAttributes.ContentState
    let look: PhaseLook

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            value
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(look.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var value: some View {
        if state.phase == .serving || state.phase == .paused {
            Text("\(state.requests)")
        } else if let progress = state.progress, !state.isOver {
            Text(progress, format: .percent.precision(.fractionLength(0)))
        } else if let rate = state.tokensPerSecond {
            Text(rate, format: .number.precision(.fractionLength(1)))
        } else {
            ElapsedText(state: state)
        }
    }

    private var unit: String {
        if state.phase == .serving || state.phase == .paused { return state.requests == 1 ? "request" : "requests" }
        if state.progress != nil, !state.isOver { return state.phase == .benchmarking ? "of the runs" : "downloaded" }
        if state.tokensPerSecond != nil { return "tokens / s" }
        return state.isOver ? "took" : "elapsed"
    }
}

/// "● Generating · detail" on the left, the running time on the right.
private struct StatusLine: View {
    let state: SapientActivityAttributes.ContentState
    let look: PhaseLook

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: look.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(look.gradient)
            Text(look.label)
                .font(.footnote.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if showsElapsed {
                ElapsedText(state: state)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String? {
        look.label == "Not updating" ? "Open Sapient to check" : state.detail
    }

    /// The hero value already shows the time when there's nothing else to show.
    private var showsElapsed: Bool {
        state.phase == .serving || state.phase == .paused || state.tokensPerSecond != nil
            || (state.progress != nil && !state.isOver)
    }
}

/// A rounded bar filled with the phase's gradient.
private struct ProgressBar: View {
    let value: Double
    let look: PhaseLook

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(look.gradient)
                    .frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

/// Up to three numbers in equal columns: speed, tokens, first token.
private struct StatsRow: View {
    let state: SapientActivityAttributes.ContentState

    var body: some View {
        let stats = stats
        if !stats.isEmpty {
            HStack(spacing: 6) {
                ForEach(stats, id: \.label) { stat in
                    VStack(spacing: 1) {
                        Text(stat.value)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(stat.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.09), in: .rect(cornerRadius: 10))
                }
            }
        }
    }

    private var stats: [(value: String, label: String)] {
        // Downloads say everything in the status line and the bar.
        if state.downloadCount > 0 { return [] }
        if state.phase == .serving || state.phase == .paused {
            guard let rate = state.tokensPerSecond else { return [] }
            return [(String(format: "%.1f", rate), "last tok/s")]
        }
        guard state.tokens > 0 || state.tokensPerSecond != nil else { return [] }
        var list: [(String, String)] = []
        // Speed is the hero value; here it would only repeat.
        if state.progress != nil, let rate = state.tokensPerSecond { list.append((String(format: "%.1f", rate), "tok/s")) }
        list.append(("\(state.tokens)", "tokens"))
        if let ttft = state.timeToFirstTokenMs { list.append(("\(ttft) ms", "first token")) }
        return list
    }
}

/// Counts up while working; frozen once the work is over.
private struct ElapsedText: View {
    let state: SapientActivityAttributes.ContentState

    var body: some View {
        if let end = state.endedAt {
            Text(Duration.seconds(end.timeIntervalSince(state.startedAt)).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 56)
        }
    }
}

/// A thin ring that fills with `value`, around whatever is inside.
private struct Ring<Content: View>: View {
    let value: Double
    let look: PhaseLook
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(max(value, 0.03), 1))
                .stroke(look.gradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content()
        }
    }
}

/// The compact Island's right side: a ring while downloading or
/// benchmarking, speed while generating, the request count while serving.
private struct CompactValue: View {
    let state: SapientActivityAttributes.ContentState
    let look: PhaseLook

    var body: some View {
        Group {
            switch state.phase {
            case .failed, .finished, .paused:
                Image(systemName: look.symbol)
                    .foregroundStyle(look.gradient)
            case .serving:
                HStack(spacing: 4) {
                    Circle()
                        .fill(look.gradient)
                        .frame(width: 6, height: 6)
                    Text("\(state.requests)")
                }
            default:
                if let progress = state.progress {
                    Ring(value: progress, look: look) {
                        Text("\(Int((progress * 100).rounded()))")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                    }
                    .frame(width: 20, height: 20)
                } else if let rate = state.tokensPerSecond {
                    Text(String(format: "%.0f t/s", rate))
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(look.tint)
                }
            }
        }
        .font(.system(.caption2, design: .rounded, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(look.tint)
    }
}

/// The smallest Island (shared with another app's activity): the mark,
/// inside a progress ring when there is progress.
private struct MinimalMark: View {
    let state: SapientActivityAttributes.ContentState
    let look: PhaseLook

    var body: some View {
        if let progress = state.progress, !state.isOver {
            Ring(value: progress, look: look) {
                SapientMark(look: look)
                    .padding(5)
            }
            .frame(width: 22, height: 22)
        } else {
            SapientMark(look: look)
                .frame(width: 18, height: 18)
        }
    }
}

// MARK: Lock Screen

private struct LockScreenView: View {
    let attributes: SapientActivityAttributes
    let state: SapientActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let look = PhaseLook(state: state, isStale: isStale)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Header(attributes: attributes, look: look)
                Spacer(minLength: 8)
                HeroValue(state: state, look: look)
            }
            StatusLine(state: state, look: look)
            if let progress = state.progress, !state.isOver {
                ProgressBar(value: progress, look: look)
            }
            StatsRow(state: state)
        }
    }
}

#Preview("Island", as: .dynamicIsland(.expanded), using: SapientActivityAttributes(title: "Request from Shortcuts", model: "qwen2.5-1.5b-q4")) {
    SapientLiveActivity()
} contentStates: {
    SapientActivityAttributes.ContentState(phase: .generating, tokens: 84, tokensPerSecond: 27.4, timeToFirstTokenMs: 182, startedAt: .now)
    SapientActivityAttributes.ContentState(phase: .downloading, detail: "412 MB of 1.1 GB", progress: 0.37, downloadCount: 1, startedAt: .now)
    SapientActivityAttributes.ContentState(phase: .serving, detail: "Waiting for requests", requests: 12, tokensPerSecond: 31.2, startedAt: .now)
    SapientActivityAttributes.ContentState(phase: .paused, detail: "Open Sapient to resume", requests: 12, startedAt: .now)
}

#Preview("Compact", as: .dynamicIsland(.compact), using: SapientActivityAttributes(title: "Models", model: "smollm2-135m-q4")) {
    SapientLiveActivity()
} contentStates: {
    SapientActivityAttributes.ContentState(phase: .downloading, progress: 0.37, downloadCount: 1, startedAt: .now)
    SapientActivityAttributes.ContentState(phase: .serving, requests: 12, startedAt: .now)
}

#Preview("Lock Screen", as: .content, using: SapientActivityAttributes(title: "Benchmark", model: "smollm2-135m-q4")) {
    SapientLiveActivity()
} contentStates: {
    SapientActivityAttributes.ContentState(phase: .benchmarking, detail: "Run 2 of 4", progress: 0.5, tokens: 256, tokensPerSecond: 31.2, startedAt: .now)
}
