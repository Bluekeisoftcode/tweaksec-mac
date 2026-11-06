import Foundation

struct DiskInfo: Equatable, Sendable {
    let volumeName: String
    let volumeURL: URL
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}
