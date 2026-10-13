// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Sizes the Island is drawn at; the panel is made to fit the largest.
enum IslandMetrics {
    /// Room beside the notch for the mark (left) and the value (right).
    static let wing: CGFloat = 74
    static let expandedWidth: CGFloat = 380
    static let expandedHeight: CGFloat = 132
    static let cornerRadius: CGFloat = 12
    static let expandedCornerRadius: CGFloat = 26
}

/// The Island: black, hanging from the top edge around the camera notch.
/// Compact, it shows the SAPIENT mark on one side of the notch and a live
/// number on the other; under the pointer it grows to show the details.
struct IslandView: View {
    let feed: ActivityFeed
    /// The notch's width and height (a made-up one on a display without).
    let notch: CGSize
    @State private var isExpanded = false

    static let brand = Color(red: 0x2A / 255, green: 0x7D / 255, blue: 1)
    static let brandLight = Color(red: 0x6A / 255, green: 0xB0 / 255, blue: 1)

    var body: some View {
        VStack(spacing: 0) {
            if let activity = feed.activity {
                island(activity)
                    .transition(.scale(scale: 0.7, anchor: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: feed.activity != nil)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: isExpanded)
    }

    private func island(_ activity: Activity) -> some View {
        let width = isExpanded ? IslandMetrics.expandedWidth : notch.width + IslandMetrics.wing * 2
        let height = isExpanded ? notch.height + IslandMetrics.expandedHeight : notch.height
        let radius = isExpanded ? IslandMetrics.expandedCornerRadius : IslandMetrics.cornerRadius
        return VStack(spacing: 0) {
            compactRow(activity)
                .frame(height: notch.height)
            if isExpanded {
                detail(activity)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .fill(.black)
        )
        .contentShape(.rect)
        .onHover { isExpanded = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sapient: \(activity.label ?? "active")")
    }

    /// Beside the notch: the mark on the left, the number on the right.
    private func compactRow(_ activity: Activity) -> some View {
        HStack(spacing: 0) {
            SapientMark()
                .fill(gradient(for: activity))
                .frame(width: 16, height: 16)
                .frame(width: IslandMetrics.wing, alignment: .center)
            Spacer(minLength: notch.width)
            Group {
                if let value = activity.value {
                    Text(value)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(gradient(for: activity))
                        .contentTransition(.numericText())
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Self.brand)
                }
            }
            .frame(width: IslandMetrics.wing, alignment: .center)
        }
    }

    private func detail(_ activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SapientMark()
                    .fill(.white)
                    .padding(8)
                    .frame(width: 36, height: 36)
                    .background(gradient(for: activity), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.isServer ? "Sapient server" : activity.model ?? "Sapient")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text((activity.isServer ? activity.model : activity.title) ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let value = activity.value {
                    Text(value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(gradient(for: activity))
                }
            }
            HStack(spacing: 6) {
                Text(activity.label ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if let detail = activity.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let started = activity.startedAt, activity.endedAt == nil {
                    Text(timerInterval: Date(timeIntervalSince1970: started)...Date.distantFuture, countsDown: false)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: 56, alignment: .trailing)
                }
            }
            if let progress = activity.progress, !activity.isOver {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(gradient(for: activity))
                            .frame(width: max(6, proxy.size.width * min(max(progress, 0), 1)))
                    }
                }
                .frame(height: 5)
            } else if let stats = stats(for: activity), !stats.isEmpty {
                HStack(spacing: 6) {
                    ForEach(stats, id: \.label) { stat in
                        HStack(spacing: 5) {
                            Text(stat.value)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text(stat.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.1), in: .rect(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func stats(for activity: Activity) -> [(value: String, label: String)]? {
        var list: [(String, String)] = []
        if activity.phase == "serving" || activity.phase == "paused" {
            if let rate = activity.tokensPerSecond { list.append((String(format: "%.1f", rate), "last tok/s")) }
            return list
        }
        if let tokens = activity.tokens, tokens > 0 { list.append(("\(tokens)", "tokens")) }
        if let ttft = activity.timeToFirstTokenMs { list.append(("\(ttft) ms", "first token")) }
        return list
    }

    /// SAPIENT blue; violet while loading, orange for benchmarks, red for
    /// failures, grey when paused: the same colours as the iPhone's Island.
    private func gradient(for activity: Activity) -> LinearGradient {
        let colors: [Color] = switch activity.phase {
        case "loading": [.indigo, .purple]
        case "benchmarking": [.orange, .yellow]
        case "failed": [.red, .orange]
        case "paused": [.gray, .gray]
        case "generating": [Self.brand, .cyan]
        default: [Self.brand, Self.brandLight]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The SAPIENT mark: the same three strokes as the app icon.
struct SapientMark: Shape {
    /// Corner points in the icon's 1024 space; the mark spans 182…842 x 186…846.
    private static let strokes: [[CGPoint]] = [
        [CGPoint(x: 360.3, y: 202.9), CGPoint(x: 447.5, y: 202.9), CGPoint(x: 733.9, y: 671.3), CGPoint(x: 650.4, y: 671.3)],
        [CGPoint(x: 259.8, y: 502.5), CGPoint(x: 805.9, y: 455.1), CGPoint(x: 805.9, y: 531.0), CGPoint(x: 218.1, y: 578.4)],
        [CGPoint(x: 337.5, y: 745.2), CGPoint(x: 694.0, y: 326.2), CGPoint(x: 720.6, y: 405.8), CGPoint(x: 366.0, y: 828.7)],
    ]
    private static let origin = CGPoint(x: 182, y: 186)
    private static let span: CGFloat = 660

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        var path = Path()
        for stroke in Self.strokes {
            let points = stroke.map { point in
                CGPoint(
                    x: rect.midX - side / 2 + (point.x - Self.origin.x) / Self.span * side,
                    y: rect.midY - side / 2 + (point.y - Self.origin.y) / Self.span * side
                )
            }
            path.addLines(points)
            path.closeSubpath()
        }
        return path
    }
}
