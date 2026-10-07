import ActivityKit
import SwiftUI
import WidgetKit

/// SAPIENT's Live Activity: the model, what it's doing and its live stats,
/// in the Dynamic Island and on the Lock Screen.
struct SapientLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SapientActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding()
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        SapientMark()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.model)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(context.attributes.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: state)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        PhaseLine(state: state)
                        StatsRow(state: state)
                    }
                }
            } compactLeading: {
                SapientMark()
                    .frame(width: 16, height: 16)
            } compactTrailing: {
                CompactValue(state: state)
            } minimal: {
                SapientMark()
                    .frame(width: 16, height: 16)
            }
            .keylineTint(.accentColor)
        }
    }
}

/// The SAPIENT mark, tinted by state colour.
private struct SapientMark: View {
    var body: some View {
        Image("SapientMark")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.tint)
    }
}

private struct LockScreenView: View {
    let attributes: SapientActivityAttributes
    let state: SapientActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SapientMark()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attributes.model)
                        .font(.headline)
                        .lineLimit(1)
                    Text(attributes.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                ElapsedText(state: state)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            PhaseLine(state: state)
            StatsRow(state: state)
        }
    }
}

/// "Generating", "Downloading · 412 MB of 1.1 GB", with a bar when there's progress.
private struct PhaseLine: View {
    let state: SapientActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(state.phase == .failed ? Color.red : Color.accentColor)
                Text(state.phase.label)
                    .font(.subheadline.weight(.medium))
                if let detail = state.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let progress = state.progress, !state.isOver {
                ProgressView(value: progress)
                    .tint(.accentColor)
            }
        }
    }

    private var symbol: String {
        switch state.phase {
        case .preparing: "hourglass"
        case .downloading: "arrow.down.circle"
        case .loading: "memorychip"
        case .generating: "text.bubble"
        case .benchmarking: "gauge.with.dots.needle.67percent"
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .serving: "antenna.radiowaves.left.and.right"
        }
    }
}

/// tok/s, tokens and time to first token, once there are any.
private struct StatsRow: View {
    let state: SapientActivityAttributes.ContentState

    var body: some View {
        if state.phase == .serving {
            HStack(spacing: 16) {
                stat("\(state.requests)", state.requests == 1 ? "request" : "requests")
                if let rate = state.tokensPerSecond {
                    stat(String(format: "%.1f", rate), "last tok/s")
                }
            }
        } else if state.tokens > 0 || state.tokensPerSecond != nil {
            HStack(spacing: 16) {
                stat(state.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "–", "tok/s")
                stat("\(state.tokens)", "tokens")
                if let ttft = state.timeToFirstTokenMs {
                    stat("\(ttft) ms", "first token")
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
                .frame(maxWidth: 52)
        }
    }
}

/// The compact Island's right side: tok/s while generating, % while downloading.
private struct CompactValue: View {
    let state: SapientActivityAttributes.ContentState

    var body: some View {
        Group {
            switch state.phase {
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .finished:
                Image(systemName: "checkmark").foregroundStyle(.tint)
            case .serving:
                Text("\(state.requests)")
            default:
                if let rate = state.tokensPerSecond {
                    Text(String(format: "%.0f t/s", rate))
                } else if let progress = state.progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .font(.caption2.monospacedDigit().weight(.semibold))
        .foregroundStyle(.tint)
    }
}

#Preview("Island", as: .dynamicIsland(.expanded), using: SapientActivityAttributes(title: "Request from Shortcuts", model: "Qwen2.5 1.5B")) {
    SapientLiveActivity()
} contentStates: {
    SapientActivityAttributes.ContentState(phase: .generating, tokens: 84, tokensPerSecond: 27.4, timeToFirstTokenMs: 182, startedAt: .now)
    SapientActivityAttributes.ContentState(phase: .downloading, detail: "412 MB of 1.1 GB", progress: 0.37, startedAt: .now)
}
