import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarPanel.shared.install()
    }
}

@main
struct TweaksecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: AppSettings
    @State private var usageStore: UsageStore
    @State private var diskStore: DiskStore
    @State private var cacheStore: CacheStore

    init() {
        // Restores the home folder grant before the cache store reads any folder.
        _ = HomeAccess.shared
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        let usageStore = UsageStore(settings: settings)
        let diskStore = DiskStore(settings: settings)
        let cacheStore = CacheStore(settings: settings)
        _usageStore = State(initialValue: usageStore)
        _diskStore = State(initialValue: diskStore)
        _cacheStore = State(initialValue: cacheStore)
        NotificationService.shared.requestAuthorization()
        MenuBarPanel.shared.content = AnyView(
            MenuContentView()
                .environment(settings)
                .environment(usageStore)
                .environment(diskStore)
                .environment(cacheStore)
        )
        HotKeyService.shared.onPress = { MenuBarPanel.shared.toggle() }
        HotKeyService.shared.hotKey = settings.showMenuHotKey
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(settings)
                .environment(usageStore)
                .environment(diskStore)
                .environment(cacheStore)
        }
    }
}
