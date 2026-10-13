// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import AppKit
import SwiftUI

// Sapient Island: shows what Sapient Studio is doing at the MacBook's
// camera notch. Sapient Studio is an iPad app, and an iPad app on a Mac
// can't draw outside its own window, so this small native app does it,
// reading `GET /v1/activity` from Sapient Studio's local API server (turn
// the server on in Sapient Studio → Settings).
//
//   swift run -c release                # port 11435
//   swift run -c release SapientIsland --port 8080
//
// No Dock icon. Right-click the Island to quit.

@MainActor
final class IslandController: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private let feed: ActivityFeed

    init(port: Int) {
        feed = ActivityFeed(port: port)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showPanel()
        feed.start()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func screensChanged() {
        panel?.orderOut(nil)
        panel = nil
        showPanel()
    }

    /// The display with the camera notch, else the main one.
    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// The notch's size on `screen`: the gap between the two halves of the
    /// menu bar. A display without one gets a notch-sized stand-in the
    /// height of the menu bar, so the Island looks the same there.
    private func notchSize(on screen: NSScreen) -> CGSize {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 180, height: max(24, menuBar))
    }

    private func showPanel() {
        guard let screen else { return }
        let notch = notchSize(on: screen)
        let width = max(IslandMetrics.expandedWidth, notch.width + IslandMetrics.wing * 2)
        let height = notch.height + IslandMetrics.expandedHeight
        let frame = NSRect(
            x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height
        )
        let panel = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar, on every Space, and over full-screen apps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        let host = PassthroughHostingView(rootView: IslandView(feed: feed, notch: notch))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.menu = quitMenu()
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func quitMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Sapient Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }
}

/// A panel that never takes the keyboard from the app you're working in.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets clicks through wherever the Island isn't drawn, so the menu bar
/// and the windows under the panel's empty area keep working.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let view = super.hitTest(point) else { return nil }
        // The hosting view itself is the transparent background.
        return view === self ? nil : view
    }
}

var port = 11435
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--port"), arguments.indices.contains(index + 1), let value = Int(arguments[index + 1]) {
    port = value
}

// Top-level code runs on the main thread; AppKit wants the main actor.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let controller = IslandController(port: port)
    application.delegate = controller
    application.setActivationPolicy(.accessory)
    application.run()
}
