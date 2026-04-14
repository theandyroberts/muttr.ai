import CoreGraphics
import Foundation

final class StubOCRService: OCRProviding, Sendable {
    private let sampleTexts: [String] = [
        "$ npm run build\nCompiling project...\nBuild succeeded in 2.3s",
        "ERROR: Module not found 'react-dom'\nnpm ERR! code MODULE_NOT_FOUND",
        "$ git push origin main\nEnumerating objects: 15, done.\nremote: Resolving deltas: 100%",
        "Tests: 42 passed, 3 failed, 45 total\nTest Suites: 5 passed, 1 failed",
        "? Do you want to continue? (y/n)",
    ]

    private let counter = Counter()

    func recognizeText(in image: CGImage) async throws -> OCRResult {
        let index = counter.next() % sampleTexts.count
        let text = sampleTexts[index]
        print("[StubOCR] Recognized: \(text.prefix(50))...")
        return OCRResult(
            fullText: text,
            blocks: [OCRTextBlock(text: text, confidence: 0.95, bounds: .zero)],
            timestamp: Date()
        )
    }
}

// Thread-safe counter
private final class Counter: Sendable {
    private let lock = NSLock()
    private var _value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let val = _value
        _value += 1
        return val
    }
}
