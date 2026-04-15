import Foundation

/// File-based logger. We must NEVER write to the user's stderr/stdout while
/// the wrapped child owns the terminal — it shreds TUIs (Claude prompts, etc.).
/// All diagnostics go to ~/Library/Logs/muttr/cli.log.
enum Log {
    private static let handle: FileHandle? = openHandle()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        guard let handle else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        handle.write(Data(line.utf8))
    }

    static var path: String {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/muttr")
        return (dir as NSString).appendingPathComponent("cli.log")
    }

    private static func openHandle() -> FileHandle? {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/muttr")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("cli.log")
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let h = FileHandle(forWritingAtPath: path) else { return nil }
        try? h.seekToEnd()
        return h
    }
}
