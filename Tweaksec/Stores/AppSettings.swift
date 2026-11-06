import Foundation
import Observation

enum DeleteMode: String, CaseIterable, Identifiable, Sendable {
    case trash
    case permanent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .trash: "Move to Trash"
        case .permanent: "Delete Permanently"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var usageSource: UsageSource { didSet { defaults.set(usageSource.rawValue, forKey: Keys.usageSource) } }
    var monthlyTokenLimit: Int { didSet { defaults.set(monthlyTokenLimit, forKey: Keys.tokenLimit) } }
    /// Empty means the boot volume.
    var diskVolumePath: String { didSet { defaults.set(diskVolumePath, forKey: Keys.volumePath) } }
    var androidProjectPaths: [String] { didSet { defaults.set(androidProjectPaths, forKey: Keys.projectPaths) } }
    var deleteMode: DeleteMode { didSet { defaults.set(deleteMode.rawValue, forKey: Keys.deleteMode) } }
    /// nil means the shortcut is turned off; stored as empty data so it stays distinct from "never set".
    var showMenuHotKey: HotKey? {
        didSet { defaults.set(showMenuHotKey.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: Keys.showMenuHotKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usageSource = defaults.string(forKey: Keys.usageSource).flatMap(UsageSource.init) ?? .claudeSubscription
        monthlyTokenLimit = defaults.object(forKey: Keys.tokenLimit) as? Int ?? 1_000_000
        diskVolumePath = defaults.string(forKey: Keys.volumePath) ?? ""
        androidProjectPaths = defaults.stringArray(forKey: Keys.projectPaths) ?? []
        deleteMode = defaults.string(forKey: Keys.deleteMode).flatMap(DeleteMode.init) ?? .trash
        showMenuHotKey = defaults.data(forKey: Keys.showMenuHotKey)
            .map { try? JSONDecoder().decode(HotKey.self, from: $0) } ?? .default
    }

    private enum Keys {
        static let usageSource = "usageSource"
        static let tokenLimit = "monthlyTokenLimit"
        static let volumePath = "diskVolumePath"
        static let projectPaths = "androidProjectPaths"
        static let deleteMode = "deleteMode"
        static let showMenuHotKey = "showMenuHotKey"
    }
}
