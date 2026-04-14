import CoreGraphics
import Foundation

final class StubCaptureService: CaptureProviding, @unchecked Sendable {
    private var continuation: AsyncStream<ScreenFrame>.Continuation?
    private var timer: Timer?
    private var _frames: AsyncStream<ScreenFrame>?

    var frames: AsyncStream<ScreenFrame> {
        if let existing = _frames { return existing }
        let stream = AsyncStream<ScreenFrame> { continuation in
            self.continuation = continuation
        }
        _frames = stream
        return stream
    }

    func startCapture(fps: Double, target: CaptureTarget) async throws {
        try await startCapture(fps: fps)
    }

    func startCapture(fps: Double) async throws {
        let interval = 1.0 / fps
        // Ensure we have the stream set up
        _ = frames

        await MainActor.run {
            self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self, let continuation = self.continuation else { return }
                // Create a small dummy CGImage
                if let image = self.createDummyImage() {
                    let frame = ScreenFrame(image: image)
                    continuation.yield(frame)
                }
            }
        }
        print("[StubCapture] Started at \(fps) fps")
    }

    func stopCapture() async {
        await MainActor.run {
            self.timer?.invalidate()
            self.timer = nil
        }
        continuation?.finish()
        continuation = nil
        print("[StubCapture] Stopped")
    }

    private func createDummyImage() -> CGImage? {
        let width = 100
        let height = 100
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
