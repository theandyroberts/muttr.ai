import Foundation

enum UrgencyLevel: Int, Codable, CaseIterable, Comparable {
    case routine = 1
    case interesting = 2
    case noteworthy = 3
    case needsInput = 4

    static func < (lhs: UrgencyLevel, rhs: UrgencyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .routine: return "Routine"
        case .interesting: return "Interesting"
        case .noteworthy: return "Noteworthy"
        case .needsInput: return "Needs Input"
        }
    }
}
