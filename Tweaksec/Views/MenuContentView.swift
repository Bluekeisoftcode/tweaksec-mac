import SwiftUI

struct MenuContentView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(UsageStore.self) private var usageStore
    @Environment(DiskStore.self) private var diskStore
    @Environment(CacheStore.self) private var cacheStore
    @State private var window: NSWindow?
    @State private var lastRefresh: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                Text("Tweaksec").font(.headline)
                Spacer()
                Button { refreshAll(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }

            UsageSection()
            Divider()
            DiskSection()
            Divider()
            if HomeAccess.shared.isGranted {
                CacheSection(group: .xcode)
                Divider()
                CacheSection(group: .android)
            } else {
                HomeAccessPrompt { refreshAll(force: true) }
            }
            Divider()

            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 420)
        .background(WindowReader(window: $window))
        // The menu window is reused between openings, so refresh whenever it becomes key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window, note.object as? NSWindow === window { refreshOnOpen() }
        }
        .onAppear(perform: refreshOnOpen)
    }

    private func refreshOnOpen() {
        // onAppear and didBecomeKey both fire on the first opening.
        guard Date.now.timeIntervalSince(lastRefresh) > 1 else { return }
        refreshAll(force: false)
    }

    private func refreshAll(force: Bool) {
        lastRefresh = .now
        diskStore.refresh()
        cacheStore.refreshSizes(force: force)
        Task { await usageStore.refresh() }
    }
}

private struct HomeAccessPrompt: View {
    let onGranted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Cache Cleanup", systemImage: "hammer")
                .font(.body.weight(.semibold))
            Text("Tweaksec needs access to your home folder to read Xcode and Android cache folders. You only need to allow this once.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow Home Folder Access…") {
                if HomeAccess.shared.request() { onGranted() }
            }
            .controlSize(.small)
        }
    }
}

private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
