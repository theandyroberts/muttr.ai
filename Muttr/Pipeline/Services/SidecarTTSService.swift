import Foundation
import AVFoundation

/// TTSProviding that speaks to a local Python sidecar running Qwen3-TTS (or similar)
/// via mlx-audio. The sidecar returns a WAV payload; we play it directly through
/// AVAudioPlayer (same pattern as TTSEngine's AVSpeechSynthesizer: play-and-done).
final class SidecarTTSService: TTSProviding, @unchecked Sendable {
    static let defaultURL = URL(string: "http://127.0.0.1:7173")!

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = SidecarTTSService.defaultURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        // First synth after cold start with ref-audio cloning can take over a
        // minute as the reference clip is tokenized and the MLX graph JITs.
        // Steady state should be well under 2 s.
        config.timeoutIntervalForRequest = 180.0
        self.session = URLSession(configuration: config)
    }

    func synthesize(_ request: TTSSpeechRequest) async throws -> TTSAudioOutput {
        let body: [String: Any] = [
            "text": request.text,
            "voice": request.voiceID,
            "rate": request.rate,
            "pitch": request.pitch,
            "urgency": request.urgency.rawValue,
        ]
        var req = URLRequest(url: baseURL.appendingPathComponent("synthesize"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/wav", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SidecarTTSError.badResponse
        }

        // Play the WAV directly. AVAudioPlayer handles all sample rates / bit
        // depths / channel counts natively — simpler and more robust than
        // hand-rolling a PCM decoder + AVAudioEngine hookup.
        let session = WAVPlaybackSession(wavData: data)
        return try await withTaskCancellationHandler {
            try await session.play()
        } onCancel: {
            session.cancel()
        }
    }

    static func isAvailable(baseURL: URL = defaultURL) async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"))
        req.timeoutInterval = 1.0
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

enum SidecarTTSError: LocalizedError {
    case badResponse
    case invalidWAV(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Bad response from TTS sidecar."
        case .invalidWAV(let msg): return "Invalid WAV: \(msg)"
        case .playbackFailed(let msg): return "Playback failed: \(msg)"
        }
    }
}

private final class WAVPlaybackSession: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let wavData: Data
    private let lock = NSLock()
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<TTSAudioOutput, Error>?
    private var resolved = false

    init(wavData: Data) {
        self.wavData = wavData
        super.init()
    }

    func play() async throws -> TTSAudioOutput {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            continuation = cont
            do {
                let p = try AVAudioPlayer(data: wavData)
                p.delegate = self
                p.prepareToPlay()
                player = p
                lock.unlock()
                if !p.play() {
                    resolve(with: .failure(SidecarTTSError.playbackFailed("AVAudioPlayer.play returned false")))
                }
            } catch {
                lock.unlock()
                resolve(with: .failure(SidecarTTSError.playbackFailed(error.localizedDescription)))
            }
        }
    }

    func cancel() {
        lock.lock()
        player?.stop()
        lock.unlock()
        resolve(with: .success(.empty))
    }

    private func resolve(with result: Result<TTSAudioOutput, Error>) {
        lock.lock()
        guard !resolved, let cont = continuation else { lock.unlock(); return }
        resolved = true
        continuation = nil
        lock.unlock()
        cont.resume(with: result)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        resolve(with: .success(.empty))
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        resolve(with: .failure(SidecarTTSError.playbackFailed(error?.localizedDescription ?? "decode error")))
    }
}

/// Minimal WAV parser: reads a PCM (8/16/24/32-bit int or 32-bit float) mono/stereo
/// file and returns Float32 interleaved samples at the file's native sample rate.
enum WAVDecoder {
    static func decodeToFloat32PCM(_ data: Data) throws -> TTSAudioOutput {
        guard data.count >= 44 else { throw SidecarTTSError.invalidWAV("too short") }
        guard data[0..<4] == Data("RIFF".utf8), data[8..<12] == Data("WAVE".utf8) else {
            throw SidecarTTSError.invalidWAV("not a RIFF/WAVE header")
        }

        var offset = 12
        var fmtFormat: UInt16 = 0
        var channels: UInt16 = 0
        var sampleRate: UInt32 = 0
        var bitsPerSample: UInt16 = 0
        var dataStart = -1
        var dataSize = 0

        while offset + 8 <= data.count {
            let chunkID = data[offset..<offset+4]
            let chunkSize = Int(data.readUInt32LE(at: offset + 4))
            let bodyStart = offset + 8
            if chunkID == Data("fmt ".utf8) {
                fmtFormat = data.readUInt16LE(at: bodyStart)
                channels = data.readUInt16LE(at: bodyStart + 2)
                sampleRate = data.readUInt32LE(at: bodyStart + 4)
                bitsPerSample = data.readUInt16LE(at: bodyStart + 14)
            } else if chunkID == Data("data".utf8) {
                dataStart = bodyStart
                dataSize = chunkSize
                break
            }
            offset = bodyStart + chunkSize + (chunkSize % 2)
        }

        guard dataStart > 0 else { throw SidecarTTSError.invalidWAV("missing data chunk") }

        let samples = try convertToFloat32(
            data: data,
            start: dataStart,
            size: dataSize,
            format: fmtFormat,
            bitsPerSample: bitsPerSample
        )

        let pcm = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return TTSAudioOutput(
            pcmData: pcm,
            sampleRate: Double(sampleRate),
            channelCount: Int(channels)
        )
    }

    private static func convertToFloat32(
        data: Data,
        start: Int,
        size: Int,
        format: UInt16,
        bitsPerSample: UInt16
    ) throws -> [Float] {
        let end = min(start + size, data.count)
        switch (format, bitsPerSample) {
        case (1, 16):
            var out = [Float]()
            out.reserveCapacity((end - start) / 2)
            var i = start
            while i + 1 < end {
                let s = Int16(bitPattern: data.readUInt16LE(at: i))
                out.append(Float(s) / 32768.0)
                i += 2
            }
            return out
        case (1, 32):
            var out = [Float]()
            out.reserveCapacity((end - start) / 4)
            var i = start
            while i + 3 < end {
                let s = Int32(bitPattern: data.readUInt32LE(at: i))
                out.append(Float(s) / 2147483648.0)
                i += 4
            }
            return out
        case (3, 32):
            var out = [Float]()
            out.reserveCapacity((end - start) / 4)
            var i = start
            while i + 3 < end {
                let bits = data.readUInt32LE(at: i)
                out.append(Float(bitPattern: bits))
                i += 4
            }
            return out
        default:
            throw SidecarTTSError.invalidWAV("unsupported format \(format) / \(bitsPerSample)-bit")
        }
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
