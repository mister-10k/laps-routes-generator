import Foundation
import CoreLocation

struct City: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let landmarkName: String
    
    // Conformance to Hashable and Equatable for selection
    static func == (lhs: City, rhs: City) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

