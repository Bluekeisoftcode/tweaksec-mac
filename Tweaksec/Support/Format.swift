import Foundation

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number)
    }
}
