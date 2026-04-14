import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            VoiceSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                }

            ModelSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }

            CloudSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Cloud", systemImage: "cloud")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Capture") {
                HStack {
                    Text("Capture FPS")
                    Spacer()
                    Picker("", selection: $appState.settings.captureFPS) {
                        Text("1 fps").tag(1.0)
                        Text("2 fps").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)
            }

            Section("Hotkey") {
                Text("Toggle narration: \(AppConstants.defaultHotkey)")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Voice

struct VoiceSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Voice Selection") {
                Picker("Voice", selection: $appState.settings.selectedVoiceID) {
                    Text("Amy (Default)").tag("en_US-amy-medium")
                    Text("Ryan").tag("en_US-ryan-medium")
                    Text("Jenny").tag("en_US-jenny-medium")
                    Text("Aria").tag("en_US-aria-medium")
                }
            }

            Section("Volume") {
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $appState.settings.volume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                }
            }

            Section("Urgency Preview") {
                VStack(alignment: .leading, spacing: 6) {
                    urgencyRow(.routine, "Routine — calm, monotone")
                    urgencyRow(.interesting, "Interesting — slightly engaged")
                    urgencyRow(.noteworthy, "Noteworthy — alert, emphasis")
                    urgencyRow(.needsInput, "Needs Input — urgent, distinct")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func urgencyRow(_ level: UrgencyLevel, _ description: String) -> some View {
        HStack {
            Circle()
                .fill(urgencyColor(level))
                .frame(width: 10, height: 10)
            Text("\(level.rawValue) - \(description)")
                .font(.caption)
        }
    }

    private func urgencyColor(_ level: UrgencyLevel) -> Color {
        switch level {
        case .routine: return .gray
        case .interesting: return .blue
        case .noteworthy: return .orange
        case .needsInput: return .red
        }
    }
}

// MARK: - Models

struct ModelSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var newModelName = ""

    var body: some View {
        Form {
            if !appState.canSelectModel {
                Section {
                    Text("Model selection requires Pro. Free tier uses the default bundled model.")
                        .foregroundColor(.secondary)
                }
            }

            Section("Current Model") {
                Text(appState.settings.selectedModelName)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Available Models") {
                if appState.modelManager.availableModels.isEmpty {
                    Text("No models loaded. Pull a model or start Ollama.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appState.modelManager.availableModels) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.name)
                                    .font(.system(.body, design: .monospaced))
                                Text(model.displaySize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if model.name == appState.settings.selectedModelName {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else if appState.canSelectModel {
                                Button("Select") {
                                    appState.settings.selectedModelName = model.name
                                    appState.rebuildPipeline()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            Section("Pull Model") {
                HStack {
                    TextField("Model name (e.g. llama3.2:1b)", text: $newModelName)
                        .textFieldStyle(.roundedBorder)
                    Button("Pull") {
                        Task {
                            try? await appState.modelManager.pullModel(name: newModelName)
                            newModelName = ""
                        }
                    }
                    .disabled(newModelName.isEmpty || appState.modelManager.isPulling)
                }
                if appState.modelManager.isPulling {
                    ProgressView(value: appState.modelManager.pullProgress)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            try? await appState.modelManager.listModels()
        }
    }
}

// MARK: - Cloud

struct CloudSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var validationMessage = ""

    var body: some View {
        Form {
            if !appState.canUseCloud {
                Section {
                    Text("Cloud narration requires Pro. Upgrade to use your own API keys.")
                        .foregroundColor(.secondary)
                }
            }

            Section("Narration Mode") {
                Picker("Mode", selection: $appState.narrationMode) {
                    Text("Local Only").tag(NarrationMode.localOnly)
                    Text("Cloud Only").tag(NarrationMode.cloudOnly)
                    Text("Hybrid").tag(NarrationMode.hybrid)
                    Text("Vision (VLM)").tag(NarrationMode.vlmCloud)
                }
                .pickerStyle(.segmented)
                .disabled(!appState.canUseCloud)

                switch appState.narrationMode {
                case .localOnly:
                    Text("All narration uses your local Ollama model.")
                        .font(.caption).foregroundColor(.secondary)
                case .cloudOnly:
                    Text("Uses cloud API with automatic local fallback.")
                        .font(.caption).foregroundColor(.secondary)
                case .hybrid:
                    Text("Routine/interesting → local. Noteworthy/urgent → cloud.")
                        .font(.caption).foregroundColor(.secondary)
                case .vlmCloud:
                    Text("Sends screenshots to a vision model — best quality, skips OCR.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section("Cloud Provider") {
                Picker("Provider", selection: $appState.settings.cloudProvider) {
                    Text("OpenAI").tag(AppSettings.CloudProvider.openAI)
                    Text("Anthropic").tag(AppSettings.CloudProvider.anthropic)
                }
                .pickerStyle(.segmented)
                .disabled(!appState.canUseCloud)
            }

            Section("API Keys (stored in Keychain)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.caption).foregroundColor(.secondary)
                    SecureField("sk-...", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!appState.canUseCloud)
                    Button("Save OpenAI Key") {
                        try? appState.keychainService.setOpenAIKey(openAIKey)
                        appState.rebuildPipeline()
                        validationMessage = "OpenAI key saved."
                    }
                    .disabled(openAIKey.isEmpty || !appState.canUseCloud)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Anthropic API Key")
                        .font(.caption).foregroundColor(.secondary)
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!appState.canUseCloud)
                    Button("Save Anthropic Key") {
                        try? appState.keychainService.setAnthropicKey(anthropicKey)
                        appState.rebuildPipeline()
                        validationMessage = "Anthropic key saved."
                    }
                    .disabled(anthropicKey.isEmpty || !appState.canUseCloud)
                }

                if !validationMessage.isEmpty {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            openAIKey = appState.keychainService.getOpenAIKey() ?? ""
            anthropicKey = appState.keychainService.getAnthropicKey() ?? ""
        }
    }
}
