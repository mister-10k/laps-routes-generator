import Foundation
import CoreLocation
import MapKit

struct PointOfInterest: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let type: String // MKPointOfInterestCategory raw value or custom
    let priority: Int // Lower = more important (1 = landmarks, 5 = generic)
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Helper to initialize from MKMapItem
    init(mapItem: MKMapItem, searchTerm: String = "") {
        self.id = UUID()
        self.name = mapItem.name ?? "Unknown POI"
        self.latitude = mapItem.placemark.coordinate.latitude
        self.longitude = mapItem.placemark.coordinate.longitude
        
        if let category = mapItem.pointOfInterestCategory {
            self.type = category.rawValue
        } else {
            self.type = "unknown"
        }
        
        // Assign priority based on category and search term
        self.priority = PointOfInterest.calculatePriority(category: mapItem.pointOfInterestCategory, searchTerm: searchTerm, name: self.name)
    }
    
    init(name: String, coordinate: CLLocationCoordinate2D, type: String) {
        self.id = UUID()
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.type = type
        self.priority = 3 // Default mid-priority
    }
    
    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, type: String, priority: Int = 3) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.type = type
        self.priority = priority
    }
    
    // MARK: - Priority Calculation
    
    /// Calculate priority score (lower = better, more important)
    /// Based on category and search term - scales to any city
    private static func calculatePriority(category: MKPointOfInterestCategory?, searchTerm: String, name: String) -> Int {
        
        // Tier 1 (Priority 1): Landmarks, monuments, national parks, major museums
        let tier1SearchTerms = ["landmark", "monument"]
        let tier1Categories: [MKPointOfInterestCategory] = [.nationalPark]
        if tier1SearchTerms.contains(searchTerm) || tier1Categories.contains(where: { $0 == category }) {
            return 1
        }
        
        // Tier 2 (Priority 2): Parks, stadiums, museums, universities
        let tier2SearchTerms = ["park", "stadium", "museum", "university", "garden", "plaza", "square"]
        let tier2Categories: [MKPointOfInterestCategory] = [.park, .stadium, .museum, .university, .zoo, .aquarium, .amusementPark]
        if tier2SearchTerms.contains(searchTerm) || tier2Categories.contains(where: { $0 == category }) {
            return 2
        }
        
        // Tier 3 (Priority 3): Cultural/historic venues
        let tier3SearchTerms = ["theater", "library", "palace", "castle", "cathedral", "beach"]
        let tier3Categories: [MKPointOfInterestCategory] = [.theater, .library, .marina, .beach]
        if tier3SearchTerms.contains(searchTerm) || tier3Categories.contains(where: { $0 == category }) {
            return 3
        }
        
        // Tier 4 (Priority 4): Generic places (churches, temples, restaurants)
        return 4
    }
    
    static func == (lhs: PointOfInterest, rhs: PointOfInterest) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
