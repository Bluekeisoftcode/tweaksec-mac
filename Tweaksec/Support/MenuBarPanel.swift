import AppKit

/// MenuBarExtra has no API to open its window, so this clicks the status item's button.
@MainActor
enum MenuBarPanel {
    static func toggle() {
        guard let button = NSApp.windows.lazy.compactMap({ statusButton(in: $0.contentView) }).first else { return }
        NSApp.activate()
        button.performClick(nil)
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap { statusButton(in: $0) }.first
    }
}
