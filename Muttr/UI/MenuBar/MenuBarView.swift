import SwiftUI
import ScreenCaptureKit

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("Muttr")
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Current narration
            if let narration = appState.pipelineStatus.lastNarration {
                HStack(alignment: .top) {
                    urgencyBadge(narration.urgencyLevel)
                    Text(narration.narration)
                        .font(.callout)
                        .lineLimit(3)
                }
                .padding(.vertical, 2)
            } else {
                Text("No narration yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Start/Stop
            if appState.isRunning {
                Button(action: stopPipeline) {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            } else {
                Button(action: startWindowPick) {
                    Label("Start — click a window", systemImage: "play.circle.fill")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button(action: startFullScreen) {
                    Label("Start — entire screen", systemImage: "display")
                }
                .font(.caption)
            }

            // Volume
            HStack {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                Slider(value: $appState.settings.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
            }

            Divider()

            if #available(macOS 14, *) {
                SettingsLink {
                    Text("Settings...")
                }
                .keyboardShortcut(",", modifiers: .command)
            } else {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            Button("Quit Muttr") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 280)
    }

    private var statusColor: Color {
        switch appState.pipelineStatus.state {
        case .running: return .green
        case .paused: return .yellow
        case .error: return .red
        case .idle: return .gray
        }
    }

    private var statusText: String {
        switch appState.pipelineStatus.state {
        case .running: return "Listening"
        case .paused: return "Paused"
        case .error(let msg): return "Error: \(msg)"
        case .idle: return "Idle"
        }
    }

    private func urgencyBadge(_ level: UrgencyLevel) -> some View {
        Text("\(level.rawValue)")
            .font(.caption2.bold())
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(urgencyColor(level))
            .clipShape(Circle())
    }

    private func urgencyColor(_ level: UrgencyLevel) -> Color {
        switch level {
        case .routine: return .gray
        case .interesting: return .blue
        case .noteworthy: return .orange
        case .needsInput: return .red
        }
    }

    private func startWindowPick() {
        // Dismiss the menu bar popover first so it's not in the way
        NSApp.deactivate()

        // Small delay to let the popover close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let picker = WindowPickerOverlay()
            picker.pick { scWindow in
                guard let scWindow else { return } // user cancelled
                Task { @MainActor in
                    await appState.pipelineCoordinator.start(
                        appState: appState,
                        target: .window(scWindow)
                    )
                }
            }
        }
    }

    private func startFullScreen() {
        Task {
            await appState.pipelineCoordinator.start(appState: appState, target: .fullScreen)
        }
    }

    private func stopPipeline() {
        Task {
            await appState.pipelineCoordinator.stop()
        }
    }
}
