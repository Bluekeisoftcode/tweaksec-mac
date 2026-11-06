import Foundation

enum DiskService {
    private static let keys: Set<URLResourceKey> = [
        .volumeLocalizedNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
    ]

    static func info(for volumeURL: URL) -> DiskInfo? {
        guard let values = try? volumeURL.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        // "Important usage" includes purgeable space, matching what Finder reports as available.
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init) ?? 0
        return DiskInfo(volumeName: values.volumeLocalizedName ?? volumeURL.lastPathComponent,
                        volumeURL: volumeURL,
                        totalBytes: Int64(total),
                        availableBytes: available)
    }

    static func mountedVolumes() -> [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys),
                                              options: [.skipHiddenVolumes]) ?? []
    }
}
