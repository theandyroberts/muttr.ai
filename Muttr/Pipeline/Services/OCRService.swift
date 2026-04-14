import Foundation
import Vision
import CoreGraphics

final class OCRService: OCRProviding, Sendable {
    func recognizeText(in image: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: .empty)
                    return
                }

                var fullText = ""
                var blocks: [OCRTextBlock] = []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string
                    let confidence = candidate.confidence

                    if !fullText.isEmpty {
                        fullText += "\n"
                    }
                    fullText += text

                    blocks.append(OCRTextBlock(
                        text: text,
                        confidence: confidence,
                        bounds: observation.boundingBox
                    ))
                }

                let result = OCRResult(
                    fullText: fullText,
                    blocks: blocks,
                    timestamp: Date()
                )
                continuation.resume(returning: result)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
