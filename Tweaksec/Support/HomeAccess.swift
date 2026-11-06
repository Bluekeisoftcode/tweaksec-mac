import AppKit
import Observation

/// The user's real home folder. Inside App Sandbox `homeDirectoryForCurrentUser` points at the app container.
enum UserHome {
    static let url: URL = {
        if let dir = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// `abbreviatingWithTildeInPath` uses the container home under App Sandbox.
    static func abbreviate(_ path: String) -> String {
        let home = url.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

/// Under App Sandbox the cache folders are reachable only after the user picks the home folder once.
/// The grant is kept as a security-scoped bookmark and restored on launch.
@MainActor
@Observable
final class HomeAccess {
    static let shared = HomeAccess()

    private(set) var isGranted: Bool
    private let defaults: UserDefaults
    private static let bookmarkKey = "homeFolderBookmark"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isGranted = !UserHome.isSandboxed
        if UserHome.isSandboxed { restore() }
    }

    @discardableResult
    func request() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = UserHome.url
        panel.message = "Select your home folder (\(UserHome.url.lastPathComponent)) so Tweaksec can measure and clean Xcode and Android caches."
        panel.prompt = "Grant Access"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        guard url.resolvingSymlinksInPath().path == UserHome.url.resolvingSymlinksInPath().path else {
            let alert = NSAlert()
            alert.messageText = "Please select your home folder"
            alert.informativeText = "Selected: \(url.path)\nRequired: \(UserHome.url.path)"
            alert.runModal()
            return false
        }
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                               relativeTo: nil),
              url.startAccessingSecurityScopedResource() else { return false }
        defaults.set(data, forKey: Self.bookmarkKey)
        isGranted = true
        return true
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            defaults.removeObject(forKey: Self.bookmarkKey)
            return
        }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                      relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        isGranted = true
    }
}
