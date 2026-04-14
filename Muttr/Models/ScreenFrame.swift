import CoreGraphics
import Foundation

struct ScreenFrame: Sendable {
    let image: CGImage
    let timestamp: Date
    let displayID: CGDirectDisplayID

    init(image: CGImage, timestamp: Date = Date(), displayID: CGDirectDisplayID = CGMainDisplayID()) {
        self.image = image
        self.timestamp = timestamp
        self.displayID = displayID
    }
}
