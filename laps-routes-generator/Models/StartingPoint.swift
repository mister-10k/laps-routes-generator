import Foundation
import CoreLocation

struct StartingPoint: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    
    // Conformance to Hashable and Equatable for selection
    static func == (lhs: StartingPoint, rhs: StartingPoint) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

