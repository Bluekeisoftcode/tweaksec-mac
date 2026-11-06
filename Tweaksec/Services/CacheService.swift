import Foundation

struct CacheService: Sendable {
    struct DeleteResult: Sendable {
        var freedBytes: Int64 = 0
        var deletedCount = 0
        var failures: [String] = []
    }

    let home: URL

    init(home: URL = UserHome.url) {
        self.home = home.standardizedFileURL
    }

    func items(for target: CacheTarget) -> [URL] {
        let fm = FileManager.default
        switch target.selector {
        case .contents(let directory):
            return (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        case .prefixed(let directory, let prefix):
            let children = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return children.filter { $0.lastPathComponent.hasPrefix(prefix) }
        case .projectBuildFolders(let root):
            guard isAndroidProject(root) else { return [] }
            let modules = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles])) ?? []
            return ([root] + modules)
                .map { $0.appendingPathComponent("build") }
                .filter(isRealDirectory)
        }
    }

    func size(of target: CacheTarget) -> Int64 {
        items(for: target).reduce(0) { $0 + allocatedSize(of: $1) }
    }

    func delete(_ target: CacheTarget, mode: DeleteMode) -> DeleteResult {
        var result = DeleteResult()
        for item in items(for: target) {
            guard isSafeToDelete(item) else {
                result.failures.append("\(item.path): path not allowed")
                continue
            }
            let size = allocatedSize(of: item)
            do {
                switch mode {
                case .trash: try FileManager.default.trashItem(at: item, resultingItemURL: nil)
                case .permanent: try FileManager.default.removeItem(at: item)
                }
                result.freedBytes += size
                result.deletedCount += 1
            } catch {
                result.failures.append("\(item.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// Only items at least two levels below the home directory may be deleted.
    func isSafeToDelete(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        let homeComponents = home.pathComponents
        return components.count >= homeComponents.count + 2
            && Array(components.prefix(homeComponents.count)) == homeComponents
            && !components.contains("..")
    }

    /// Rejects the home folder, its direct children and anything without a Gradle build script,
    /// so a mistakenly added folder cannot expose unrelated `build` directories.
    func isAndroidProject(_ root: URL) -> Bool {
        let scripts = ["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"]
        return isSafeToDelete(root)
            && isRealDirectory(root)
            && scripts.contains { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
    }

    private func isRealDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .totalFileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? 0) }

        // The enumerator does not descend into symbolic links.
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                              errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var done = false
        while !done {
            // Drain per file: the cooperative thread's pool is only emptied when the task ends,
            // so walking a large tree like Gradle caches would otherwise hold every URL in memory.
            autoreleasepool {
                guard !Task.isCancelled, let child = enumerator.nextObject() as? URL else { done = true; return }
                guard let v = try? child.resourceValues(forKeys: keys), v.isSymbolicLink != true, v.isDirectory != true else { return }
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
