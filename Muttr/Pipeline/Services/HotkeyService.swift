import Foundation
import HotKey
import Carbon

@MainActor
final class HotkeyService {
    private var hotKey: HotKey?
    private var toggleAction: (() -> Void)?

    func register(action: @escaping () -> Void) {
        self.toggleAction = action
        // ⌘⇧M
        hotKey = HotKey(key: .m, modifiers: [.command, .shift])
        hotKey?.keyDownHandler = { [weak self] in
            self?.toggleAction?()
        }
    }

    func unregister() {
        hotKey = nil
        toggleAction = nil
    }
}
