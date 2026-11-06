import AppKit
import SwiftUI

/// Owns the status item and its panel, because MenuBarExtra has no API to open its window from code.
@MainActor
final class MenuBarPanel: NSObject {
    static let shared = MenuBarPanel()

    var content: AnyView?

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickMonitor: Any?

    private override init() {}

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Tweaksec")
            button.target = self
            button.action = #selector(toggle)
            // Acting on mouse down keeps a click from closing the panel and reopening it on mouse up.
            button.sendAction(on: .leftMouseDown)
        }
        statusItem = item
    }

    @objc func toggle() {
        if panel?.isVisible == true { close() } else { open() }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem?.button?.highlight(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func open() {
        guard let panel = panel ?? makePanel() else { return }
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        reposition()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        statusItem?.button?.highlight(true)
        // The app may stay inactive after a hotkey press, so losing key status alone misses these.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeUnlessPointerOnStatusItem()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(otherAppDidActivate),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    private func makePanel() -> NSPanel? {
        guard let content else { return nil }
        let panel = StatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 12)

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])
        panel.contentView = background
        panel.setContentSize(hostingView.fittingSize)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(panelDidResignKey), name: NSWindow.didResignKeyNotification, object: panel)
        center.addObserver(self, selector: #selector(panelDidResize), name: NSWindow.didResizeNotification, object: panel)
        return panel
    }

    /// Hangs the panel below the status item and keeps it on the status item's screen.
    private func reposition() {
        guard let panel, let anchor = statusItem?.button?.window else { return }
        let size = panel.frame.size
        var x = anchor.frame.minX
        if let screen = anchor.screen?.visibleFrame {
            x = min(x, screen.maxX - size.width - 8)
            x = max(x, screen.minX + 8)
        }
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.frame.minY - 4))
    }

    /// A click on the status item also looks like a click elsewhere; closing for it would make toggle() reopen the panel.
    private func closeUnlessPointerOnStatusItem() {
        if let anchor = statusItem?.button?.window, anchor.frame.contains(NSEvent.mouseLocation) { return }
        close()
    }

    @objc private func panelDidResignKey() {
        closeUnlessPointerOnStatusItem()
    }

    @objc private func panelDidResize() {
        reposition()
        panel?.invalidateShadow()
    }

    @objc private func otherAppDidActivate(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app != NSRunningApplication.current { closeUnlessPointerOnStatusItem() }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Borderless windows refuse key status by default, which would disable the panel's controls.
private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        MenuBarPanel.shared.close()
    }
}
