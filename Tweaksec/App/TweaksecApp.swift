import SwiftUI

@main
struct TweaksecApp: App {
    @State private var settings: AppSettings
    @State private var usageStore: UsageStore
    @State private var diskStore: DiskStore
    @State private var cacheStore: CacheStore

    init() {
        // Restores the home folder grant before the cache store reads any folder.
        _ = HomeAccess.shared
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _usageStore = State(initialValue: UsageStore(settings: settings))
        _diskStore = State(initialValue: DiskStore(settings: settings))
        _cacheStore = State(initialValue: CacheStore(settings: settings))
        NotificationService.shared.requestAuthorization()
        HotKeyService.shared.onPress = { MenuBarPanel.toggle() }
        HotKeyService.shared.hotKey = settings.showMenuHotKey
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(settings)
                .environment(usageStore)
                .environment(diskStore)
                .environment(cacheStore)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(usageStore)
                .environment(diskStore)
                .environment(cacheStore)
        }
    }
}
