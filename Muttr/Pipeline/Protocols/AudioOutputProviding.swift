import Foundation

protocol AudioOutputProviding: AnyObject, Sendable {
    func play(_ audio: TTSAudioOutput) async throws
    func stop()
    var volume: Float { get set }
}
