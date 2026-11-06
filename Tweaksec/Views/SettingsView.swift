import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            UsageSettingsTab()
                .tabItem { Label("AI Usage", systemImage: "sparkles") }
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProjectsSettingsTab()
                .tabItem { Label("Android Projects", systemImage: "folder") }
        }
        .frame(width: 520, height: 440)
    }
}

private struct UsageSettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UsageStore.self) private var usageStore
    @State private var keyInput = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Usage Source", selection: $settings.usageSource) {
                    ForEach(UsageSource.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.usageSource) { usageStore.sourceChanged() }
                HStack {
                    Text("Status")
                    Spacer()
                    statusText
                }
            } footer: {
                Text(settings.usageSource.footer)
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if let keySetup = settings.usageSource.keySetup {
                Section(keySetup.label) {
                    SecureField(keySetup.label, text: $keyInput,
                                prompt: Text(usageStore.hasAPIKey ? "Saved (type to replace)" : keySetup.placeholder))
                    HStack {
                        Button("Save") {
                            usageStore.setAPIKey(keyInput)
                            keyInput = ""
                        }
                        .disabled(keyInput.isEmpty)
                        Button("Delete", role: .destructive) { usageStore.setAPIKey(nil) }
                            .disabled(!usageStore.hasAPIKey)
                        Spacer()
                        Link("Get a Key", destination: keySetup.url)
                            .font(.subheadline)
                    }
                    if settings.usageSource != .deepSeekBalance {
                        TextField("Monthly Token Limit", value: $settings.monthlyTokenLimit, format: .number)
                    }
                }
            }

        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusText: some View {
        switch usageStore.state {
        case .idle: Text("Fetched when the menu opens").foregroundStyle(.secondary)
        case .notConfigured(let message): Text(message).foregroundStyle(.secondary).lineLimit(2)
        case .loading: ProgressView().controlSize(.small)
        case .loaded: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message): Text(message).foregroundStyle(.red).lineLimit(2)
        }
    }
}

private extension UsageSource {
    var footer: String {
        switch self {
        case .claudeSubscription:
            "Reads your Claude Code login (Keychain, read-only) to show Pro/Max 5-hour and weekly limits. Checking does not cost anything or count against your limits. This uses a private endpoint that may change without notice. Usage is fetched only when the menu opens; due to rate limits, reopening within 3 minutes shows the previous values."
        case .anthropicAdmin:
            "Shows your organization's API token usage for this month. Requires an Admin API key (sk-ant-admin…), stored in the Keychain."
        case .openAIAdmin:
            "Shows your organization's API token usage for this month. Requires an Admin key (sk-admin-…), stored in the Keychain."
        case .deepSeekBalance:
            "Shows your prepaid DeepSeek balance. DeepSeek has no token usage API. Any API key works; it is stored in the Keychain."
        case .codexSubscription:
            "Reads your Codex CLI login (~/.codex/auth.json, read-only) to show ChatGPT plan 5-hour and weekly limits. Requires home folder access. This uses a private endpoint that may change without notice. If the token has expired, run Codex once to refresh it."
        case .geminiCLI:
            "Reads your Gemini CLI Google login (~/.gemini/oauth_creds.json, read-only) to show per-model daily request quotas. Requires home folder access. This uses a private endpoint that may change without notice. The token lasts about an hour; run Gemini CLI to refresh it."
        }
    }

    var keySetup: (label: String, placeholder: String, url: URL)? {
        switch self {
        case .anthropicAdmin:
            ("Admin API Key", "sk-ant-admin01-…", URL(string: "https://console.anthropic.com/settings/admin-keys")!)
        case .openAIAdmin:
            ("Admin Key", "sk-admin-…", URL(string: "https://platform.openai.com/settings/organization/admin-keys")!)
        case .deepSeekBalance:
            ("API Key", "sk-…", URL(string: "https://platform.deepseek.com/api_keys")!)
        case .claudeSubscription, .codexSubscription, .geminiCLI:
            nil
        }
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DiskStore.self) private var diskStore
    @State private var volumes: [URL] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hotKeyConflict = HotKeyService.shared.registrationFailed

    var body: some View {
        @Bindable var settings = settings
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Picker("Monitored Disk", selection: $settings.diskVolumePath) {
                Text("Startup Disk").tag("")
                ForEach(volumes.filter { $0.path != "/" }, id: \.path) { url in
                    Text(DiskService.info(for: url)?.volumeName ?? url.lastPathComponent).tag(url.path)
                }
            }
            .onChange(of: settings.diskVolumePath) { diskStore.refresh() }
            Picker("Delete Method", selection: $settings.deleteMode) {
                ForEach(DeleteMode.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Show Menu Shortcut") {
                HStack {
                    HotKeyRecorder(hotKey: $settings.showMenuHotKey)
                    Button("Reset") { settings.showMenuHotKey = .default }
                        .disabled(settings.showMenuHotKey == .default)
                }
            }
            .onChange(of: settings.showMenuHotKey) { _, hotKey in
                HotKeyService.shared.hotKey = hotKey
                hotKeyConflict = HotKeyService.shared.registrationFailed
            }
            if hotKeyConflict {
                Text("This shortcut is already in use by another app.")
                    .font(.subheadline).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .onAppear { volumes = DiskService.mountedVolumes() }
    }
}

private struct ProjectsSettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CacheStore.self) private var cacheStore
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adds the build folders (root and modules) of these projects to the cache cleanup targets.")
                .font(.subheadline).foregroundStyle(.secondary)
            List(settings.androidProjectPaths, id: \.self, selection: $selection) { path in
                Text(UserHome.abbreviate(path))
            }
            .listStyle(.bordered)
            HStack {
                Button("Add…", action: addProject)
                Button("Remove") {
                    settings.androidProjectPaths.removeAll { $0 == selection }
                    selection = nil
                    cacheStore.reloadTargets()
                }
                .disabled(selection == nil)
            }
        }
        .padding()
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let service = CacheService()
        let valid = panel.urls.filter(service.isAndroidProject)
        let rejected = panel.urls.filter { !valid.contains($0) }
        let new = valid.map(\.path).filter { !settings.androidProjectPaths.contains($0) }
        settings.androidProjectPaths += new
        if !rejected.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Folders that are not Android projects were not added"
            alert.informativeText = rejected.map { UserHome.abbreviate($0.path) }.joined(separator: "\n")
                + "\n\nOnly folders at least two levels below your home folder that contain settings.gradle or build.gradle(.kts) can be added."
            alert.runModal()
        }
        cacheStore.reloadTargets()
    }
}
