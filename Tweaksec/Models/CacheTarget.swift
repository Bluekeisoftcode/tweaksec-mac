import Foundation

enum CacheGroup: String, CaseIterable, Identifiable, Sendable {
    case xcode
    case android

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcode: "Xcode"
        case .android: "Android Studio"
        }
    }

    /// Bundle identifiers used to warn when the IDE is running during cleanup.
    var runningAppBundleIDs: [String] {
        switch self {
        case .xcode: ["com.apple.dt.Xcode"]
        case .android: ["com.google.android.studio"]
        }
    }
}

struct CacheTarget: Identifiable, Hashable, Sendable {
    enum Selector: Hashable, Sendable {
        /// Every item inside `directory` (equivalent to `directory/*`).
        case contents(of: URL)
        /// Items inside `directory` whose name starts with `prefix` (equivalent to `directory/prefix*`).
        case prefixed(URL, prefix: String)
        /// `build` folders at the project root and one level below (module folders).
        case projectBuildFolders(URL)
    }

    let id: String
    let group: CacheGroup
    let name: String
    let selector: Selector
    /// Extra warning shown in the confirmation dialog.
    var warning: String?

    /// Folder revealed in Finder.
    var revealURL: URL {
        switch selector {
        case .contents(let url), .prefixed(let url, _), .projectBuildFolders(let url): url
        }
    }

    var displayPath: String {
        let path: String
        switch selector {
        case .contents(let url): path = url.path + "/*"
        case .prefixed(let url, let prefix): path = url.appendingPathComponent(prefix).path + "*"
        case .projectBuildFolders(let url): path = url.path + "/**/build"
        }
        return UserHome.abbreviate(path)
    }
}

extension CacheTarget {
    static func defaults(home: URL = UserHome.url) -> [CacheTarget] {
        let dev = home.appendingPathComponent("Library/Developer/Xcode")
        let caches = home.appendingPathComponent("Library/Caches")
        return [
            CacheTarget(id: "xcode.deriveddata", group: .xcode, name: "DerivedData",
                        selector: .contents(of: dev.appendingPathComponent("DerivedData"))),
            CacheTarget(id: "xcode.devicesupport", group: .xcode, name: "iOS DeviceSupport",
                        selector: .contents(of: dev.appendingPathComponent("iOS DeviceSupport")),
                        warning: "Symbol files will be downloaded again when a device is connected."),
            CacheTarget(id: "xcode.archives", group: .xcode, name: "Archives",
                        selector: .contents(of: dev.appendingPathComponent("Archives")),
                        warning: "Distribution archives (.xcarchive) and dSYMs will be deleted."),
            CacheTarget(id: "xcode.caches", group: .xcode, name: "Xcode Caches",
                        selector: .contents(of: caches.appendingPathComponent("com.apple.dt.Xcode"))),
            CacheTarget(id: "android.cache", group: .android, name: "Android cache",
                        selector: .contents(of: home.appendingPathComponent(".android/cache"))),
            CacheTarget(id: "android.gradle", group: .android, name: "Gradle caches",
                        selector: .contents(of: home.appendingPathComponent(".gradle/caches"))),
            CacheTarget(id: "android.avd", group: .android, name: "AVD (Emulators)",
                        selector: .contents(of: home.appendingPathComponent(".android/avd")),
                        warning: "All emulators you created will be deleted."),
            CacheTarget(id: "android.studiocaches", group: .android, name: "Android Studio Caches",
                        selector: .prefixed(caches.appendingPathComponent("Google"), prefix: "AndroidStudio")),
        ]
    }

    static func projectBuild(_ projectURL: URL) -> CacheTarget {
        CacheTarget(id: "android.project.\(projectURL.path)", group: .android,
                    name: projectURL.lastPathComponent + " build",
                    selector: .projectBuildFolders(projectURL))
    }
}
