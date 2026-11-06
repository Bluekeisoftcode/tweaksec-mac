import SwiftUI

struct DiskSection: View {
    @Environment(DiskStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Disk", systemImage: "internaldrive")
                .font(.body.weight(.semibold))

            if let info = store.info {
                Text("\(info.volumeName): \(Format.bytes(info.usedBytes)) of \(Format.bytes(info.totalBytes)) used (\(Format.bytes(info.availableBytes)) free)")
                    .font(.subheadline)
                ProgressView(value: info.usedFraction)
                    .tint(UsageColor.tint(for: info.usedFraction))
            } else {
                Text("Unable to read disk information.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
