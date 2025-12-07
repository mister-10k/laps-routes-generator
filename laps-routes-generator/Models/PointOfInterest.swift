import Foundation
import CoreLocation
import MapKit

struct PointOfInterest: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let type: String // MKPointOfInterestCategory raw value or custom
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Helper to initialize from MKMapItem
    init(mapItem: MKMapItem) {
        self.id = UUID()
        self.name = mapItem.name ?? "Unknown POI"
        self.latitude = mapItem.placemark.coordinate.latitude
        self.longitude = mapItem.placemark.coordinate.longitude
        
        if let category = mapItem.pointOfInterestCategory {
            self.type = category.rawValue
        } else {
            self.type = "unknown"
        }
    }
    
    init(name: String, coordinate: CLLocationCoordinate2D, type: String) {
        self.id = UUID()
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.type = type
    }
    
    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, type: String) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.type = type
    }
    
    static func == (lhs: PointOfInterest, rhs: PointOfInterest) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
