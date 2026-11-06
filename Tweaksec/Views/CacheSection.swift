import SwiftUI

struct CacheSection: View {
    let group: CacheGroup
    @Environment(CacheStore.self) private var store

    var body: some View {
        let targets = store.targets(in: group)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("\(group.title) Caches", systemImage: group == .xcode ? "hammer" : "shippingbox")
                    .font(.body.weight(.semibold))
                Spacer()
                if store.isCalculating { ProgressView().controlSize(.mini) }
                sizeText(store.totalSize(in: group))
                Button("Delete All") { confirmAndDelete(targets) }
                    .controlSize(.small)
                    .disabled(targets.allSatisfy { (store.sizes[$0.id] ?? 0) == 0 } || targets.contains { store.busy.contains($0.id) })
            }

            ForEach(targets) { target in
                CacheRow(target: target) { confirmAndDelete([target]) }
            }
        }
    }

    private func confirmAndDelete(_ targets: [CacheTarget]) {
        let total = targets.compactMap { store.sizes[$0.id] }.reduce(0, +)
        var lines = targets.map { "• \($0.displayPath)" }
        lines += targets.compactMap { $0.warning.map { "⚠️ \($0)" } }
        let running = group.runningAppBundleIDs.contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
        if running { lines.append("⚠️ \(group.title) is running. Quit it before deleting.") }
        lines.append("\nTotal \(Format.bytes(total))")
        let title = targets.count == 1 ? "Delete \(targets[0].name)" : "Delete All \(group.title) Caches"
        guard Confirm.destructive(title: title, message: lines.joined(separator: "\n")) else { return }
        Task { await store.delete(targets) }
    }

    @ViewBuilder
    private func sizeText(_ size: Int64?) -> some View {
        Text(size.map(Format.bytes) ?? "Calculating…")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

private struct CacheRow: View {
    let target: CacheTarget
    let onDelete: () -> Void
    @Environment(CacheStore.self) private var store

    var body: some View {
        let size = store.sizes[target.id]
        HStack(spacing: 6) {
            Text(target.name)
                .font(.body)
                .help(target.displayPath)
            Spacer()
            if store.busy.contains(target.id) {
                ProgressView().controlSize(.mini)
            } else {
                Text(size.map(Format.bytes) ?? "…")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                NSWorkspace.shared.open(target.revealURL)
            } label: {
                Image(systemName: "folder")
            }
            .help("Show in Finder")
            .disabled(!FileManager.default.fileExists(atPath: target.revealURL.path))
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .help("Delete")
            .disabled((size ?? 0) == 0 || store.busy.contains(target.id))
        }
        .buttonStyle(.borderless)
    }
}
