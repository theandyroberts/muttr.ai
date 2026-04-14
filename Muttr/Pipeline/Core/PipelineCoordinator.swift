import Combine
import CoreGraphics
import Foundation

@MainActor
final class PipelineCoordinator {
    private weak var appState: AppState?

    private let captureService: any CaptureProviding
    private let ocrService: any OCRProviding
    private let diffEngine: any DiffProviding
    private let narrationRouter: NarrationRouter
    private let vlmProvider: (any VLMNarrationProviding)?
    private let ttsEngine: any TTSProviding
    private let audioService: any AudioOutputProviding

    private var pipelineTask: Task<Void, Never>?
    private var previousOCR: OCRResult = .empty
    private var previousFrame: CGImage?
    private var lastNarrationTime: Date = .distantPast
    private var lastNarrationText: String = ""
    private let minNarrationInterval: TimeInterval = 5.0

    init(
        capture: any CaptureProviding,
        ocr: any OCRProviding,
        diff: any DiffProviding,
        narrationRouter: NarrationRouter,
        vlm: (any VLMNarrationProviding)? = nil,
        tts: any TTSProviding,
        audio: any AudioOutputProviding
    ) {
        self.captureService = capture
        self.ocrService = ocr
        self.diffEngine = diff
        self.narrationRouter = narrationRouter
        self.vlmProvider = vlm
        self.ttsEngine = tts
        self.audioService = audio
    }

    func start(appState: AppState, target: CaptureTarget = .fullScreen) async {
        guard !appState.pipelineStatus.state.isRunning else { return }
        self.appState = appState
        appState.pipelineStatus.state = .running
        previousOCR = .empty
        hasBaseline = false

        // Speak warmup, pre-load model, then confirm ready
        await speak("Alright, let me get set up.", urgency: .routine, appState: appState)
        await narrationRouter.warmup()

        do {
            try await captureService.startCapture(fps: appState.settings.captureFPS, target: target)
        } catch {
            appState.pipelineStatus.state = .error("Capture failed: \(error.localizedDescription)")
            return
        }

        await speak("Ok, watching.", urgency: .routine, appState: appState)

        pipelineTask = Task { [weak self] in
            guard let self else { return }
            await self.runPipelineLoop()
        }
    }

    func stop() async {
        pipelineTask?.cancel()
        pipelineTask = nil
        await captureService.stopCapture()
        audioService.stop()
        appState?.pipelineStatus.state = .idle
    }

    private var hasBaseline = false

    private var useVLM: Bool {
        guard let appState else { return false }
        return appState.narrationMode == .vlmCloud && vlmProvider != nil
    }

    private func runPipelineLoop() async {
        for await frame in captureService.frames {
            guard let appState, !Task.isCancelled else { break }

            do {
                let narration: NarrationResult

                if useVLM {
                    // VLM path: send raw frames, skip OCR + Diff
                    if !hasBaseline {
                        previousFrame = frame.image
                        hasBaseline = true
                        continue
                    }

                    // Throttle
                    let now = Date()
                    guard now.timeIntervalSince(lastNarrationTime) >= minNarrationInterval else {
                        previousFrame = frame.image
                        continue
                    }

                    narration = try await vlmProvider!.generateNarration(
                        currentFrame: frame.image,
                        previousFrame: previousFrame,
                        timeout: AppConstants.vlmTimeoutSeconds
                    )

                    previousFrame = frame.image

                } else {
                    // Text path: OCR → Diff → NarrationRouter
                    let ocrResult = try await ocrService.recognizeText(in: frame.image)

                    if !hasBaseline {
                        previousOCR = ocrResult
                        hasBaseline = true
                        continue
                    }

                    let diff = diffEngine.diff(previous: previousOCR, current: ocrResult)
                    previousOCR = ocrResult

                    guard diff.significantChange else { continue }

                    let now = Date()
                    guard now.timeIntervalSince(lastNarrationTime) >= minNarrationInterval else { continue }

                    narration = await narrationRouter.narrate(
                        diff: diff,
                        tier: appState.tier,
                        mode: appState.narrationMode
                    )
                }

                // Skip duplicate narrations
                guard narration.narration != lastNarrationText else { continue }

                lastNarrationTime = Date()
                lastNarrationText = narration.narration

                await MainActor.run {
                    appState.pipelineStatus.lastNarration = narration
                    appState.pipelineStatus.framesProcessed += 1
                }

                // TTS
                let speechRequest = TTSSpeechRequest(
                    text: narration.narration,
                    urgency: narration.urgencyLevel,
                    voiceID: appState.settings.selectedVoiceID
                )
                let audio = try await ttsEngine.synthesize(speechRequest)

                // Play
                try await audioService.play(audio)

            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        appState.pipelineStatus.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func speak(_ text: String, urgency: UrgencyLevel, appState: AppState) async {
        let narration = NarrationResult(narration: text, urgency: urgency.rawValue)
        appState.pipelineStatus.lastNarration = narration

        let request = TTSSpeechRequest(
            text: text,
            urgency: urgency,
            voiceID: appState.settings.selectedVoiceID
        )
        if let audio = try? await ttsEngine.synthesize(request) {
            try? await audioService.play(audio)
        }
    }
}
