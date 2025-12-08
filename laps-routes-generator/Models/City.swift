import Foundation
import CoreLocation

struct City: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let continent: String
    let startingPoints: [StartingPoint]
    
    // Convenience computed property for backward compatibility
    var coordinate: CLLocationCoordinate2D {
        startingPoints.first?.coordinate ?? CLLocationCoordinate2D()
    }
    
    var landmarkName: String {
        startingPoints.first?.name ?? ""
    }
    
    // Conformance to Hashable and Equatable for selection
    static func == (lhs: City, rhs: City) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

