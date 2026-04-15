import Darwin
import Foundation

struct PTYChild: Sendable {
    let pid: pid_t
    let masterFD: Int32
}

enum PTYError: Error, LocalizedError {
    case forkFailed(String)

    var errorDescription: String? {
        switch self {
        case .forkFailed(let msg): return "forkpty failed: \(msg)"
        }
    }
}

enum PTYBridge {
    /// Fork a child process attached to a new pseudo-terminal.
    /// Parent gets the master fd; child execvp's the target and inherits the slave as stdio.
    static func spawn(command: String, args: [String]) throws -> PTYChild {
        var master: Int32 = 0
        var ws = winsize()
        _ = pty_getwinsize(STDIN_FILENO, &ws)

        var term = termios()
        _ = tcgetattr(STDIN_FILENO, &term)

        let pid = forkpty(&master, nil, &term, &ws)
        if pid < 0 {
            throw PTYError.forkFailed(String(cString: strerror(errno)))
        }
        if pid == 0 {
            let argv = ([command] + args).map { strdup($0) } + [UnsafeMutablePointer<CChar>?(nil)]
            _ = execvp(command, argv)
            perror("execvp")
            _exit(127)
        }
        return PTYChild(pid: pid, masterFD: master)
    }

    static func resize(fd: Int32, to size: winsize) {
        var s = size
        _ = pty_setwinsize(fd, &s)
    }

    static func currentWinSize() -> winsize {
        var ws = winsize()
        _ = pty_getwinsize(STDIN_FILENO, &ws)
        return ws
    }
}
