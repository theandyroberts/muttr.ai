import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var tier: UserTier = .trial
    @Published var narrationMode: NarrationMode = .localOnly
    @Published var pipelineStatus = PipelineStatus()
    @Published var settings = AppSettings()
    @Published var isOnboarded: Bool = false

    @Published var hasScreenCapturePermission: Bool = false
    @Published var hasAccessibilityPermission: Bool = false

    let keychainService = KeychainService()
    let modelManager = ModelManager()

    lazy var pipelineCoordinator: PipelineCoordinator = {
        buildPipelineCoordinator()
    }()

    var isRunning: Bool {
        pipelineStatus.state.isRunning
    }

    var canUseCloud: Bool {
        tier == .pro || tier == .trial
    }

    var canSelectModel: Bool {
        tier == .pro || tier == .trial
    }

    func rebuildPipeline() {
        pipelineCoordinator = buildPipelineCoordinator()
    }

    private func buildPipelineCoordinator() -> PipelineCoordinator {
        let localNarration = OllamaService(modelName: settings.selectedModelName)

        var cloudNarration: (any NarrationProviding)?
        if canUseCloud {
            switch settings.cloudProvider {
            case .openAI:
                if let key = keychainService.getOpenAIKey(), !key.isEmpty {
                    cloudNarration = CloudAPIService(provider: .openAI, apiKey: key)
                }
            case .anthropic:
                if let key = keychainService.getAnthropicKey(), !key.isEmpty {
                    cloudNarration = CloudAPIService(provider: .anthropic, apiKey: key)
                }
            }
        }

        // VLM provider for vision-based narration (Path C)
        var vlmNarration: (any VLMNarrationProviding)?
        if narrationMode == .vlmCloud && canUseCloud {
            switch settings.cloudProvider {
            case .openAI:
                if let key = keychainService.getOpenAIKey(), !key.isEmpty {
                    vlmNarration = CloudVLMService(provider: .openAI, apiKey: key)
                }
            case .anthropic:
                if let key = keychainService.getAnthropicKey(), !key.isEmpty {
                    vlmNarration = CloudVLMService(provider: .anthropic, apiKey: key)
                }
            }
        }

        let router = NarrationRouter(local: localNarration, cloud: cloudNarration)

        return PipelineCoordinator(
            capture: ScreenCaptureService(),
            ocr: OCRService(),
            diff: DiffEngine(),
            narrationRouter: router,
            vlm: vlmNarration,
            tts: TTSEngine(),
            audio: AudioService()
        )
    }
}
