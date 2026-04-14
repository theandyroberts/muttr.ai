import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics

final class ScreenCaptureService: NSObject, CaptureProviding, @unchecked Sendable {
    private var stream: SCStream?
    private var continuation: AsyncStream<ScreenFrame>.Continuation?
    private var _frames: AsyncStream<ScreenFrame>?
    private(set) var captureTarget: CaptureTarget = .fullScreen

    var frames: AsyncStream<ScreenFrame> {
        if let existing = _frames { return existing }
        let stream = AsyncStream<ScreenFrame> { continuation in
            self.continuation = continuation
        }
        _frames = stream
        return stream
    }

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// List all capturable windows (visible, with titles)
    static func availableWindows() async throws -> [CapturableWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows.compactMap { window in
            guard let app = window.owningApplication,
                  !app.bundleIdentifier.hasPrefix("com.apple.WindowManager"),
                  window.isOnScreen else {
                return nil
            }
            let appName = app.applicationName
            let title = window.title ?? ""
            // Skip tiny windows (toolbars, popovers)
            guard window.frame.width > 200 && window.frame.height > 200 else { return nil }
            return CapturableWindow(
                id: window.windowID,
                title: title,
                appName: appName,
                scWindow: window
            )
        }
    }

    func startCapture(fps: Double) async throws {
        try await startCapture(fps: fps, target: .fullScreen)
    }

    func startCapture(fps: Double, target: CaptureTarget) async throws {
        _ = frames
        self.captureTarget = target

        let filter: SCContentFilter
        let width: Int
        let height: Int

        switch target {
        case .fullScreen:
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                throw CaptureError.noDisplay
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            width = Int(display.width)
            height = Int(display.height)
            print("[ScreenCapture] Targeting full screen \(width)x\(height)")

        case .window(let scWindow):
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
            width = Int(scWindow.frame.width)
            height = Int(scWindow.frame.height)
            print("[ScreenCapture] Targeting window: \(scWindow.title ?? "untitled") (\(width)x\(height))")
        }

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 3

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await scStream.startCapture()
        self.stream = scStream

        print("[ScreenCapture] Started at \(fps) fps")
    }

    func stopCapture() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        continuation?.finish()
        continuation = nil
        _frames = nil
        print("[ScreenCapture] Stopped")
    }
}

extension ScreenCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let frame = ScreenFrame(image: cgImage)
        continuation?.yield(frame)
    }
}

enum CaptureError: LocalizedError {
    case noDisplay
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found for screen capture."
        case .permissionDenied: return "Screen recording permission is required."
        }
    }
}
