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
        
        // Sort by priority (lower = more important)
        let sortedPOIs = allPOIs.sorted { $0.priority < $1.priority }
        
        // Log priority distribution
        let tier1Count = sortedPOIs.filter { $0.priority == 1 }.count
        let tier2Count = sortedPOIs.filter { $0.priority == 2 }.count
        let tier3Count = sortedPOIs.filter { $0.priority == 3 }.count
        let tier4Count = sortedPOIs.filter { $0.priority == 4 }.count
        print("  Total unique POIs found: \(sortedPOIs.count) (landmarks:\(tier1Count) parks/museums:\(tier2Count) cultural:\(tier3Count) other:\(tier4Count))")
        
        return sortedPOIs
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
        
        return validItems.map { PointOfInterest(mapItem: $0, searchTerm: term) }
    }
}
