import Foundation

protocol CaptureProviding: AnyObject, Sendable {
    func startCapture(fps: Double) async throws
    func startCapture(fps: Double, target: CaptureTarget) async throws
    func stopCapture() async
    var frames: AsyncStream<ScreenFrame> { get }
}
