import Foundation
import MapKit

class POIService {
    static let shared = POIService()
    
    private let categories: [MKPointOfInterestCategory] = [
        .park,
        .museum,
        .stadium,
        .theater,
        .university,
        .library,
        .zoo,
        .amusementPark,
        .aquarium,
        .nationalPark,
        .marina,
        .beach
    ]
    
    // Search terms to find interesting POIs
    private let searchTerms = [
        "park",
        "museum",
        "stadium",
        "landmark",
        "monument",
        "plaza",
        "square",
        "garden",
        "theater",
        "university",
        "library",
        "beach",
        "temple",
        "cathedral",
        "church",
        "castle",
        "palace",
        "restaurant"
    ]
    
    func fetchPOIs(near coordinate: CLLocationCoordinate2D, radiusInMeters: Double) async throws -> [PointOfInterest] {
        print("  Fetching POIs near \(coordinate.latitude), \(coordinate.longitude) with radius \(radiusInMeters)m")
        
        var allPOIs: [PointOfInterest] = []
        var seenNames = Set<String>()
        
        // Search using multiple terms to get variety
        for term in searchTerms {
            do {
                let pois = try await searchForTerm(term, near: coordinate, radiusInMeters: radiusInMeters)
                print("    '\(term)' returned \(pois.count) results")
                
                for poi in pois {
                    // Deduplicate by name
                    if !seenNames.contains(poi.name) {
                        seenNames.insert(poi.name)
                        allPOIs.append(poi)
                    }
                }
            } catch {
                print("    '\(term)' search failed: \(error.localizedDescription)")
                // Continue with other terms
            }
            
            // Small delay to avoid rate limiting
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        print("  Total unique POIs found: \(allPOIs.count)")
        return allPOIs
    }
    
    private func searchForTerm(_ term: String, near coordinate: CLLocationCoordinate2D, radiusInMeters: Double) async throws -> [PointOfInterest] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusInMeters * 2,
            longitudinalMeters: radiusInMeters * 2
        )
        request.resultTypes = .pointOfInterest
        
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        
        // Filter to only items with names
        let validItems = response.mapItems.filter { $0.name != nil }
        
        return validItems.map { PointOfInterest(mapItem: $0) }
    }
}
