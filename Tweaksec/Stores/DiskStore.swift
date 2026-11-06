import Foundation
import Observation

@MainActor
@Observable
final class DiskStore {
    private(set) var info: DiskInfo?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func refresh() {
        let path = settings.diskVolumePath
        let url = path.isEmpty ? URL(fileURLWithPath: "/") : URL(fileURLWithPath: path)
        info = DiskService.info(for: url) ?? DiskService.info(for: URL(fileURLWithPath: "/"))
    }
}
