import AVFoundation
import Darwin
import Foundation

// MARK: - Arg parsing

struct CLIOptions {
    var voice: String = ""  // empty = system default (AVSpeech) / model default (sidecar)
    var model: String = AppConstants.defaultLocalModel
    var useSidecarTTS: Bool = false
    var sidecarURL: URL = SidecarTTSService.defaultURL
    var narrate: Bool = true
    var pov: NarrationPOV = .documentary
    var listVoices: Bool = false
    var testMode: Bool = false
    var claudeTail: Bool? = nil     // nil = auto-detect from command
    var command: String = ""
    var args: [String] = []
}

func parseArgs(_ raw: [String]) -> CLIOptions? {
    var opts = CLIOptions()
    var i = 1
    var sawDoubleDash = false
    while i < raw.count {
        let a = raw[i]
        if !sawDoubleDash {
            switch a {
            case "--voice":
                i += 1; if i < raw.count { opts.voice = raw[i] }
            case "--model":
                i += 1; if i < raw.count { opts.model = raw[i] }
            case "--sidecar":
                opts.useSidecarTTS = true
            case "--sidecar-url":
                i += 1
                if i < raw.count, let url = URL(string: raw[i]) {
                    opts.sidecarURL = url
                    opts.useSidecarTTS = true
                }
            case "--no-narrate":
                opts.narrate = false
            case "--list-voices":
                opts.listVoices = true
            case "--test":
                opts.testMode = true
            case "--claude-tail":
                opts.claudeTail = true
            case "--no-claude-tail":
                opts.claudeTail = false
            case "--pov":
                i += 1
                if i < raw.count, let pov = NarrationPOV(rawValue: raw[i]) {
                    opts.pov = pov
                } else {
                    let valid = NarrationPOV.allCases.map(\.rawValue).joined(separator: ", ")
                    FileHandle.standardError.write(Data("muttr: invalid --pov; valid: \(valid)\n".utf8))
                    return nil
                }
            case "--":
                sawDoubleDash = true
            case "-h", "--help":
                return nil
            default:
                if opts.command.isEmpty {
                    opts.command = a
                    sawDoubleDash = true
                } else {
                    opts.args.append(a)
                }
            }
        } else {
            if opts.command.isEmpty {
                opts.command = a
            } else {
                opts.args.append(a)
            }
        }
        i += 1
    }
    if opts.listVoices || opts.testMode { return opts }
    return opts.command.isEmpty ? nil : opts
}

func printUsage() {
    let povList = NarrationPOV.allCases.map(\.rawValue).joined(separator: " | ")
    let usage = """
    muttr — narrate a CLI tool's output

    Usage:
      muttr [options] -- <command> [args...]
      muttr --list-voices [--sidecar]
      muttr --test [--sidecar] [--voice NAME]

    Options:
      --voice ID           System voice name / identifier, or for --sidecar a preset name
                           or path to a reference .wav (default: system default)
      --model NAME         Ollama model for narration (default: \(AppConstants.defaultLocalModel))
      --pov STYLE          Narration point of view: \(povList) (default: documentary)
      --sidecar            Use local TTS sidecar instead of system voice
      --sidecar-url URL    Sidecar URL (default: \(SidecarTTSService.defaultURL.absoluteString))
      --list-voices        Print available voices and exit
      --test               Speak a short sample in the chosen voice and exit
      --claude-tail        Read Claude Code's JSONL transcripts for narration
                           (auto-enabled when wrapping the `claude` command)
      --no-claude-tail     Force PTY-only narration even when wrapping claude
      --no-narrate         PTY-wrap only, no narration (debug)
      -h, --help           This help

    Examples:
      muttr -- claude "write a function that reverses a string"
      muttr --voice Samantha -- claude "..."
      muttr --pov firstPerson --voice Alex -- claude "run the tests and fix anything red"
      muttr --sidecar --voice ~/voices/alice.wav -- claude "..."

    """
    FileHandle.standardError.write(Data(usage.utf8))
}

func runVoiceTest(opts: CLIOptions) async {
    let sample = """
        Voice test. I'll narrate what's happening on your screen, like this. \
        If a test fails, you'll hear it. If the agent needs your input, you'll hear that too. \
        Keeping or changing me?
        """

    let tts: any TTSProviding
    if opts.useSidecarTTS {
        if await SidecarTTSService.isAvailable(baseURL: opts.sidecarURL) {
            tts = SidecarTTSService(baseURL: opts.sidecarURL)
        } else {
            let msg = "muttr: sidecar unreachable at \(opts.sidecarURL.absoluteString). Start it with ./sidecar/run.sh\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(1)
        }
    } else {
        tts = TTSEngine()
    }

    let label = opts.voice.isEmpty ? "<default>" : opts.voice
    let backend = opts.useSidecarTTS ? "sidecar" : "system"
    print("muttr: speaking sample — voice=\(label) backend=\(backend)")

    let request = TTSSpeechRequest(text: sample, urgency: .routine, voiceID: opts.voice)
    let audio = AudioService()
    do {
        let output = try await tts.synthesize(request)
        try await audio.play(output)
    } catch {
        FileHandle.standardError.write(Data("muttr: voice test failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

func printSidecarVoices(url: URL) async {
    var req = URLRequest(url: url.appendingPathComponent("voices"))
    req.timeoutInterval = 2.0
    do {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            FileHandle.standardError.write(Data("muttr: sidecar returned non-200 for /voices\n".utf8))
            return
        }
        struct Clip: Decodable { let name: String; let path: String; let kind: String }
        struct Response: Decodable { let model: String; let voice_dir: String; let clips: [Clip] }
        let body = try JSONDecoder().decode(Response.self, from: data)
        var out = "Sidecar voices (model: \(body.model))\n"
        out += "Reference clips in \(body.voice_dir):\n\n"
        if body.clips.isEmpty {
            out += "  (none yet — drop 5-10 second .wav clips into that directory)\n"
        } else {
            for c in body.clips {
                out += "  • \(c.name)\n"
            }
        }
        out += "\nUse with: muttr --sidecar --voice <name>   or   --voice /path/to/clip.wav\n"
        out += "Cloning is zero-shot: a 5-10s clean reference is enough.\n"
        FileHandle.standardOutput.write(Data(out.utf8))
    } catch {
        FileHandle.standardError.write(Data(
            "muttr: sidecar unreachable at \(url.absoluteString) — start it with ./sidecar/run.sh\n".utf8
        ))
    }
}

func printVoices() {
    let voices = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") }
        .sorted { $0.name < $1.name }

    func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    var out = "System voices (en-*):\n\n"
    out += "  \(pad("NAME", 20)) \(pad("LANG", 8)) IDENTIFIER\n"
    for v in voices {
        out += "  \(pad(v.name, 20)) \(pad(v.language, 8)) \(v.identifier)\n"
    }
    out += "\n"
    out += "Pass --voice with any of:\n"
    out += "  • just the NAME       (e.g. --voice Samantha)\n"
    out += "  • NAME:LANG           (e.g. --voice Eddy:en-GB) — disambiguates duplicates\n"
    out += "  • the full IDENTIFIER (e.g. --voice com.apple.voice.compact.en-GB.Daniel)\n\n"
    out += "For --sidecar with Qwen3-TTS, pass a preset name the model recognises, or\n"
    out += "a path to a 5-10 second reference .wav for voice cloning.\n"
    FileHandle.standardOutput.write(Data(out.utf8))
}

// MARK: - Signal handling

final class SignalTrap {
    static let shared = SignalTrap()
    var onWinch: (@Sendable () -> Void)?
    var onExit: (@Sendable () -> Void)?

    func install() {
        signal(SIGWINCH, { _ in SignalTrap.shared.onWinch?() })
        signal(SIGINT,  { _ in SignalTrap.shared.onExit?() })
        signal(SIGTERM, { _ in SignalTrap.shared.onExit?() })
        signal(SIGPIPE, SIG_IGN)
    }
}

// MARK: - Entry

guard let opts = parseArgs(CommandLine.arguments) else {
    printUsage()
    exit(1)
}

if opts.listVoices {
    if opts.useSidecarTTS {
        await printSidecarVoices(url: opts.sidecarURL)
    } else {
        printVoices()
    }
    exit(0)
}

if opts.testMode {
    await runVoiceTest(opts: opts)
    exit(0)
}

let rawMode = RawMode()
rawMode.enable()

var cleanupOnce = false
func cleanup() {
    guard !cleanupOnce else { return }
    cleanupOnce = true
    rawMode.restore()
}

SignalTrap.shared.install()
SignalTrap.shared.onExit = {
    cleanup()
    _exit(130)
}

let child: PTYChild
do {
    child = try PTYBridge.spawn(command: opts.command, args: opts.args)
} catch {
    cleanup()
    FileHandle.standardError.write(Data("muttr: \(error.localizedDescription)\n".utf8))
    exit(1)
}

SignalTrap.shared.onWinch = {
    let ws = PTYBridge.currentWinSize()
    PTYBridge.resize(fd: child.masterFD, to: ws)
}

// Narrator wiring (optional). Probe the sidecar once before deciding —
// silently fall back to system voice if it's not running.
Log.write("muttr starting; cmd=\(opts.command) args=\(opts.args.joined(separator: " "))")
Log.write("log path: \(Log.path)")

let narrator: TerminalNarrator? = opts.narrate ? await {
    Log.write("narration POV: \(opts.pov.rawValue) voice: \(opts.voice.isEmpty ? "<default>" : opts.voice)")
    let ollama = OllamaService(modelName: opts.model, pov: opts.pov)
    var tts: any TTSProviding = TTSEngine()
    if opts.useSidecarTTS {
        if await SidecarTTSService.isAvailable(baseURL: opts.sidecarURL) {
            tts = SidecarTTSService(baseURL: opts.sidecarURL)
            Log.write("TTS: sidecar at \(opts.sidecarURL.absoluteString)")
        } else {
            // Hard-fail: falling back to AVSpeech silently is worse than not starting.
            rawMode.restore()
            let msg = """
                muttr: --sidecar set but sidecar unreachable at \(opts.sidecarURL.absoluteString).
                       Start it with ./sidecar/run.sh (or drop --sidecar).

                """
            FileHandle.standardError.write(Data(msg.utf8))
            exit(1)
        }
    } else {
        Log.write("TTS: system voice (AVSpeechSynthesizer)")
    }
    let audio = AudioService()
    return TerminalNarrator(narrator: ollama, tts: tts, audio: audio, voiceID: opts.voice)
}() : nil

// Decide narration input source. JSONL tailing is much cleaner for Claude —
// it delivers already-structured events, no TUI chrome, no keystroke echoes —
// so when the wrapped command is `claude` we route through that and skip the
// PTY segmenter. For everything else (aider, bash, etc.) we use the segmenter.
let commandLooksLikeClaude = (opts.command as NSString).lastPathComponent.lowercased() == "claude"
let useClaudeTail = opts.claudeTail ?? commandLooksLikeClaude
Log.write("input source: \(useClaudeTail ? "claude JSONL transcripts" : "PTY stream segmenter")")

let segmenter = StreamSegmenter { segment in
    guard !useClaudeTail else { return }
    narrator?.submit(segment: segment)
}

var claudeTailer: ClaudeTranscriptTailer?
if useClaudeTail, let narrator {
    claudeTailer = ClaudeTranscriptTailer { segment in
        narrator.submit(segment: segment)
    }
    let tailer = claudeTailer!
    Task { await tailer.start() }
}

if let narrator {
    Task { await narrator.warmup() }
}

// MARK: - I/O loop

let masterFD = child.masterFD
// Set master fd non-blocking
let flags = fcntl(masterFD, F_GETFL, 0)
_ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

let readQueue = DispatchQueue(label: "ai.mattr.muttr.pty.read")
let stdinQueue = DispatchQueue(label: "ai.mattr.muttr.stdin.read")

let masterSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: readQueue)
masterSource.setEventHandler {
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(masterFD, &buf, buf.count)
        if n > 0 {
            let data = Data(bytes: buf, count: n)
            // mirror to stdout
            _ = data.withUnsafeBytes { write(STDOUT_FILENO, $0.baseAddress, n) }
            // feed narration pipe
            Task { await segmenter.ingest(data) }
        } else if n == 0 {
            masterSource.cancel()
            return
        } else {
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            masterSource.cancel()
            return
        }
    }
}
masterSource.resume()

let stdinSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: stdinQueue)
stdinSource.setEventHandler {
    var buf = [UInt8](repeating: 0, count: 1024)
    let n = read(STDIN_FILENO, &buf, buf.count)
    if n > 0 {
        _ = write(masterFD, buf, n)
        // Tell the segmenter the user just typed — any PTY output arriving in
        // the next few hundred ms is almost certainly an echo of this keystroke
        // and should not be narrated.
        Task { await segmenter.noteTyping() }
    } else if n == 0 {
        stdinSource.cancel()
    }
}
stdinSource.resume()

// Wait for the child in the background queue; resume when it exits.
let exitCode: Int32 = await withCheckedContinuation { cont in
    DispatchQueue(label: "ai.mattr.muttr.wait").async {
        var status: Int32 = 0
        _ = waitpid(child.pid, &status, 0)
        masterSource.cancel()
        stdinSource.cancel()
        let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        cont.resume(returning: code)
    }
}

await segmenter.finish()
if let tailer = claudeTailer {
    await tailer.stop()
}
// Wait for the narration queue to fully drain before we exit so the last
// observation actually finishes speaking.
if let narrator {
    await narrator.drain()
}
cleanup()
exit(exitCode)
