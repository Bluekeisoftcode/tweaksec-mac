import SwiftUI

struct UsageSection: View {
    @Environment(UsageStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.lastSnapshot?.planName ?? settings.usageSource.menuTitle, systemImage: "sparkles")
                .font(.body.weight(.semibold))

            if let snapshot = store.lastSnapshot {
                ForEach(snapshot.windows) { WindowRow(window: $0) }
                if let tokens = snapshot.tokens { tokenView(tokens) }
                ForEach(snapshot.balances) { balanceView($0) }
                Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            switch store.state {
            case .notConfigured(let message):
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            case .loading where store.lastSnapshot == nil:
                ProgressView().controlSize(.small)
            case .failed(let message):
                Text(message).font(.subheadline).foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func tokenView(_ tokens: TokenUsage) -> some View {
        let limit = max(settings.monthlyTokenLimit, 1)
        let fraction = min(Double(tokens.totalTokens) / Double(limit), 1)
        Text("This month \(Format.number(tokens.totalTokens)) / \(Format.number(settings.monthlyTokenLimit)) tokens")
            .font(.system(.body, design: .monospaced))
        ProgressView(value: fraction)
            .tint(UsageColor.tint(for: fraction))
        Text("Input \(Format.number(tokens.inputTokens + tokens.cacheCreationTokens + tokens.cacheReadTokens)) · Output \(Format.number(tokens.outputTokens))")
            .font(.subheadline).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func balanceView(_ balance: UsageBalance) -> some View {
        Text("Balance \(balance.total.formatted(.currency(code: balance.currency)))")
            .font(.system(.body, design: .monospaced))
        Text("Topped up \(balance.toppedUp.formatted(.currency(code: balance.currency))) · Granted \(balance.granted.formatted(.currency(code: balance.currency)))")
            .font(.subheadline).foregroundStyle(.secondary)
    }
}

private struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        let fraction = min(max(window.percent / 100, 0), 1)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.title).font(.body)
                Spacer()
                Text("\(Int(window.percent.rounded()))%")
                    .font(.body.monospacedDigit().weight(.medium))
            }
            ProgressView(value: fraction)
                .tint(UsageColor.tint(for: fraction))
            if let resetsAt = window.resetsAt {
                Text("Resets \(resetsAt.formatted(.relative(presentation: .numeric))) · \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

enum UsageColor {
    static func tint(for fraction: Double) -> Color {
        switch fraction {
        case 0.9...: .red
        case 0.8...: .orange
        default: .accentColor
        }
    }
}
