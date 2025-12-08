import Foundation

enum DirectionPreference: String, CaseIterable, Codable, Hashable {
    case noPreference = "No Preference"
    case north = "North"
    case east = "East"
    case south = "South"
    case west = "West"
    
    var icon: String {
        switch self {
        case .noPreference:
            return "circle"
        case .north:
            return "arrow.up.circle"
        case .east:
            return "arrow.right.circle"
        case .south:
            return "arrow.down.circle"
        case .west:
            return "arrow.left.circle"
        }
    }
}

