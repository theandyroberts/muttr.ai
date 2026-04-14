import AppKit
import ScreenCaptureKit

/// Full-screen transparent overlay that lets the user click a window to select it.
/// Highlights the window under the cursor as the mouse moves.
class WindowPickerOverlay: NSObject {
    private var overlayWindow: NSWindow?
    private var highlightWindow: NSWindow?
    private var completion: ((SCWindow?) -> Void)?
    private var windowInfoList: [[String: Any]] = []
    private var scWindows: [SCWindow] = []
    private var currentHighlightFrame: CGRect = .zero
    private var trackingMonitor: Any?
    private var keyMonitor: Any?

    func pick(completion: @escaping (SCWindow?) -> Void) {
        self.completion = completion

        Task {
            // Get ScreenCaptureKit windows for later matching
            if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) {
                self.scWindows = content.windows.filter { $0.isOnScreen }
            }

            // Get CGWindow list for hit-testing
            if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                self.windowInfoList = list.filter { info in
                    let layer = info[kCGWindowLayer as String] as? Int ?? 0
                    let alpha = info[kCGWindowAlpha as String] as? Double ?? 0
                    return layer == 0 && alpha > 0
                }
            }

            await MainActor.run {
                self.showOverlay()
            }
        }
    }

    @MainActor
    private func showOverlay() {
        guard let screen = NSScreen.main else { return }

        // Full-screen transparent overlay to capture clicks
        let overlay = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.level = .statusBar
        overlay.isOpaque = false
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.15)
        overlay.ignoresMouseEvents = false
        overlay.hasShadow = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.orderFrontRegardless()
        self.overlayWindow = overlay

        // Highlight window (yellow border around hovered window)
        let highlight = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        highlight.level = .statusBar + 1
        highlight.isOpaque = false
        highlight.backgroundColor = .clear
        highlight.ignoresMouseEvents = true
        highlight.hasShadow = false

        let borderView = BorderView(frame: .zero)
        highlight.contentView = borderView
        self.highlightWindow = highlight

        // Track mouse movement
        trackingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

        // Also track global mouse events (for clicks outside the overlay)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.cancel()
                return nil
            }
            return event
        }

        NSCursor.crosshair.push()
    }

    private func handleEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            updateHighlight(at: NSEvent.mouseLocation)
        case .leftMouseUp:
            selectWindow(at: NSEvent.mouseLocation)
        default:
            break
        }
    }

    private func updateHighlight(at screenPoint: NSPoint) {
        // Convert to CG coordinates (flipped Y)
        guard let screen = NSScreen.main else { return }
        let cgPoint = CGPoint(x: screenPoint.x, y: screen.frame.height - screenPoint.y)

        // Find window under cursor
        for info in windowInfoList {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"] else { continue }

            let bounds = CGRect(x: x, y: y, width: w, height: h)
            if bounds.contains(cgPoint) {
                // Convert back to NSScreen coordinates
                let nsRect = NSRect(
                    x: bounds.origin.x,
                    y: screen.frame.height - bounds.origin.y - bounds.height,
                    width: bounds.width,
                    height: bounds.height
                )

                if nsRect != currentHighlightFrame {
                    currentHighlightFrame = nsRect
                    highlightWindow?.setFrame(nsRect, display: true)
                    highlightWindow?.orderFrontRegardless()
                }
                return
            }
        }
    }

    private func selectWindow(at screenPoint: NSPoint) {
        guard let screen = NSScreen.main else {
            cancel()
            return
        }
        let cgPoint = CGPoint(x: screenPoint.x, y: screen.frame.height - screenPoint.y)

        // Find which CGWindow was clicked
        var selectedWindowID: CGWindowID?
        for info in windowInfoList {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }

            let bounds = CGRect(x: x, y: y, width: w, height: h)
            if bounds.contains(cgPoint) {
                selectedWindowID = windowID
                break
            }
        }

        // Match to SCWindow
        var selectedSCWindow: SCWindow?
        if let windowID = selectedWindowID {
            selectedSCWindow = scWindows.first { $0.windowID == windowID }
        }

        teardown()
        completion?(selectedSCWindow)
    }

    private func cancel() {
        teardown()
        completion?(nil)
    }

    private func teardown() {
        NSCursor.pop()
        if let monitor = trackingMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        trackingMonitor = nil
        keyMonitor = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        highlightWindow?.orderOut(nil)
        highlightWindow = nil
    }
}

/// Simple view that draws a colored border
private class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemYellow.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 4
        path.stroke()
    }
}
