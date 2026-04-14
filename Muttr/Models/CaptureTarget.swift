import Foundation
import ScreenCaptureKit

enum CaptureTarget {
    case fullScreen
    case window(SCWindow)
}

struct CapturableWindow: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let scWindow: SCWindow

    var displayName: String {
        if title.isEmpty {
            return appName
        }
        return "\(appName) — \(title)"
    }
}
