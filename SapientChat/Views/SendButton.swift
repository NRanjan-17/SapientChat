import SwiftUI

/// The composer's round action button. Send (↑) when there is text, Stop
/// (■) while a reply streams; the symbol morphs between the two, springs
/// when it becomes enabled, bounces on send and pulses while generating.
/// Every motion is skipped under Reduce Motion.
struct SendButton: View {
    enum Mode {
        case send
        case stop
    }

    let mode: Mode
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var diameter = 34.0
    @State private var taps = 0

    private var symbol: String {
        switch mode {
        case .send: "arrow.up"
        case .stop: "stop.fill"
        }
    }

    var body: some View {
        Button(action: tap) {
            Image(systemName: symbol)
                .font(.body.bold())
                .foregroundStyle(isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                .frame(width: diameter, height: diameter)
                .background(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary), in: .circle)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.up, options: .nonRepeating, value: reduceMotion ? 0 : taps)
                .symbolEffect(.pulse, options: .repeating, isActive: mode == .stop && !reduceMotion)
                .scaleEffect(isEnabled || reduceMotion ? 1 : 0.88)
        }
        .buttonStyle(PressableButtonStyle())
        // ⌘Return sends from a hardware keyboard (Return adds a line);
        // ⌘. stops, from the Chat menu.
        .keyboardShortcut(.return, modifiers: .command)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(!isEnabled)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isEnabled)
        .animation(reduceMotion ? nil : .snappy, value: mode)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(mode == .send ? "Send" : "Stop")
    }

    private func tap() {
        taps += 1
        action()
    }
}

#Preview {
    HStack {
        SendButton(mode: .send, isEnabled: true, action: {})
        SendButton(mode: .send, isEnabled: false, action: {})
        SendButton(mode: .stop, isEnabled: true, action: {})
    }
}
