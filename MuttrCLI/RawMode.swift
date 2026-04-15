import Darwin

/// Puts the terminal into cbreak/raw mode so keystrokes pass straight through to the child PTY.
/// Restore on deinit or on signal.
final class RawMode {
    private var original = termios()
    private var active = false

    func enable() {
        guard !active, isatty(STDIN_FILENO) != 0 else { return }
        _ = tcgetattr(STDIN_FILENO, &original)
        var raw = original
        cfmakeraw(&raw)
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        active = true
    }

    func restore() {
        guard active else { return }
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        active = false
    }

    deinit { restore() }
}
