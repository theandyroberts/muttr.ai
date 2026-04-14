import Foundation

final class NarrationRouter: Sendable {
    private let localProvider: any NarrationProviding
    private let cloudProvider: (any NarrationProviding)?
    private let urgencyClassifier = UrgencyClassifier()

    init(local: any NarrationProviding, cloud: (any NarrationProviding)? = nil) {
        self.localProvider = local
        self.cloudProvider = cloud
    }

    func warmup() async {
        if let ollama = localProvider as? OllamaService {
            await ollama.warmup()
        }
    }

    func narrate(
        diff: TextDiff,
        tier: UserTier,
        mode: NarrationMode
    ) async -> NarrationResult {
        let preUrgency = urgencyClassifier.classify(diff)

        switch resolveStrategy(tier: tier, mode: mode, urgency: preUrgency) {
        case .local:
            return await narrateLocal(diff: diff)
        case .cloud:
            return await narrateCloudWithFallback(diff: diff)
        case .hybrid(let urgencyThreshold):
            if preUrgency >= urgencyThreshold {
                return await narrateCloudWithFallback(diff: diff)
            } else {
                return await narrateLocal(diff: diff)
            }
        }

    }

    private enum Strategy {
        case local
        case cloud
        case hybrid(cloudAbove: UrgencyLevel)
    }

    private func resolveStrategy(tier: UserTier, mode: NarrationMode, urgency: UrgencyLevel) -> Strategy {
        switch tier {
        case .free:
            return .local
        case .pro, .trial:
            switch mode {
            case .localOnly:
                return .local
            case .cloudOnly:
                if cloudProvider != nil {
                    return .cloud
                }
                return .local
            case .hybrid:
                if cloudProvider != nil {
                    return .hybrid(cloudAbove: .noteworthy)
                }
                return .local
            case .vlmCloud:
                // VLM mode is handled by PipelineCoordinator directly;
                // if the router is called, fall back to local.
                return .local
            }
        }
    }

    private func narrateLocal(diff: TextDiff) async -> NarrationResult {
        do {
            return try await localProvider.generateNarration(
                for: diff,
                timeout: AppConstants.Performance.narrationTarget
            )
        } catch {
            return NarrationResult(
                narration: "Something changed but I couldn't parse it.",
                urgency: UrgencyLevel.routine.rawValue
            )
        }
    }

    private func narrateCloudWithFallback(diff: TextDiff) async -> NarrationResult {
        guard let cloud = cloudProvider else {
            return await narrateLocal(diff: diff)
        }

        do {
            return try await cloud.generateNarration(
                for: diff,
                timeout: AppConstants.cloudTimeoutSeconds
            )
        } catch {
            // Cloud failed — fall back to local (never silence)
            return await narrateLocal(diff: diff)
        }
    }
}
