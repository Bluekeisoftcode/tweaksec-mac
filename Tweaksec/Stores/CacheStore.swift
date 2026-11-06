import Foundation
import Observation

@MainActor
@Observable
final class CacheStore {
    private(set) var targets: [CacheTarget] = []
    private(set) var sizes: [CacheTarget.ID: Int64] = [:]
    private(set) var busy: Set<CacheTarget.ID> = []
    private(set) var isCalculating = false

    private let settings: AppSettings
    private let service: CacheService
    private var sizeTask: Task<Void, Never>?
    private var lastCalculated: Date = .distantPast
    private static let reuseInterval: TimeInterval = 300

    init(settings: AppSettings, service: CacheService = CacheService()) {
        self.settings = settings
        self.service = service
        reloadTargets(recalculate: false)
    }

    func reloadTargets(recalculate: Bool = true) {
        let projects = settings.androidProjectPaths.map { CacheTarget.projectBuild(URL(fileURLWithPath: $0)) }
        targets = CacheTarget.defaults(home: service.home) + projects
        let ids = Set(targets.map(\.id))
        sizes = sizes.filter { ids.contains($0.key) }
        if recalculate { refreshSizes() }
    }

    func targets(in group: CacheGroup) -> [CacheTarget] {
        targets.filter { $0.group == group }
    }

    func totalSize(in group: CacheGroup) -> Int64? {
        let values = targets(in: group).map { sizes[$0.id] }
        guard !values.contains(where: { $0 == nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }

    /// Walking cache folders is the app's most expensive work, so results are reused for
    /// `reuseInterval` unless `force` is set, and a scan already in progress is left running.
    func refreshSizes(force: Bool = true) {
        if !force && (isCalculating || Date.now.timeIntervalSince(lastCalculated) < Self.reuseInterval) { return }
        sizeTask?.cancel()
        isCalculating = true
        // Targets are measured one at a time to keep disk I/O and CPU use low.
        sizeTask = Task {
            for target in targets where !busy.contains(target.id) {
                let size = await measure(target)
                if Task.isCancelled { return }
                sizes[target.id] = size
            }
            lastCalculated = .now
            isCalculating = false
        }
    }

    /// Runs off the main actor and stops the file walk when the calling task is cancelled.
    private func measure(_ target: CacheTarget) async -> Int64 {
        let service = service
        let task = Task.detached(priority: .utility) { service.size(of: target) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func delete(_ targets: [CacheTarget]) async {
        let targets = targets.filter { !busy.contains($0.id) }
        guard !targets.isEmpty else { return }
        let service = service
        let mode = settings.deleteMode
        busy.formUnion(targets.map(\.id))

        var total = CacheService.DeleteResult()
        for target in targets {
            let result = await Task.detached(priority: .userInitiated) { service.delete(target, mode: mode) }.value
            total.freedBytes += result.freedBytes
            total.deletedCount += result.deletedCount
            total.failures += result.failures
            sizes[target.id] = await Task.detached(priority: .utility) { service.size(of: target) }.value
            busy.remove(target.id)
        }

        let name = targets.count == 1 ? targets[0].name : "\(targets[0].group.title) caches"
        if total.failures.isEmpty {
            NotificationService.shared.post(title: "\(name) cleaned",
                                            body: "Freed \(Format.bytes(total.freedBytes)) (\(total.deletedCount) items)")
        } else {
            let detail = total.failures.prefix(3).joined(separator: "\n")
            NotificationService.shared.post(title: "\(name): some items failed to delete",
                                            body: "Freed \(Format.bytes(total.freedBytes)), \(total.failures.count) failed\n\(detail)")
        }
    }
}
