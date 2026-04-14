import SwiftUI

@main
struct MuttrApp: App {
    @StateObject private var appState = AppState()
    private let hotkeyService = HotkeyService()

    var body: some Scene {
        MenuBarExtra("Muttr", systemImage: "waveform") {
            MenuBarView()
                .environmentObject(appState)
                .task {
                    setupHotkey()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    @MainActor
    private func setupHotkey() {
        hotkeyService.register { [weak appState] in
            guard let appState else { return }
            Task { @MainActor in
                if appState.isRunning {
                    await appState.pipelineCoordinator.stop()
                } else {
                    await appState.pipelineCoordinator.start(appState: appState)
                }
            }
        }
    }
}
