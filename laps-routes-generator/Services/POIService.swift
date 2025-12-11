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
    
    // Rate limiting: Apple allows 50 requests per 60 seconds
    private let maxRequestsPerWindow = 50
    private let windowDurationSeconds = 60.0
    private var requestTimestamps: [Date] = []
    private let requestLock = NSLock()
    
    // Default delay between requests (spread 18 requests across ~25 seconds to be safe)
    private let defaultDelayNanoseconds: UInt64 = 1_500_000_000 // 1.5 seconds
    
    func fetchPOIs(near coordinate: CLLocationCoordinate2D, radiusInMeters: Double) async throws -> [PointOfInterest] {
        print("  Fetching POIs near \(coordinate.latitude), \(coordinate.longitude) with radius \(radiusInMeters)m")
        
        var allPOIs: [PointOfInterest] = []
        var seenNames = Set<String>()
        
        // Search using multiple terms to get variety
        for term in searchTerms {
            do {
                let pois = try await searchForTermWithRetry(term, near: coordinate, radiusInMeters: radiusInMeters)
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
            
            // Delay between requests to avoid rate limiting
            try? await Task.sleep(nanoseconds: defaultDelayNanoseconds)
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
    
    private func searchForTermWithRetry(_ term: String, near coordinate: CLLocationCoordinate2D, radiusInMeters: Double, maxRetries: Int = 3) async throws -> [PointOfInterest] {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                // Check rate limit before making request
                try await waitForRateLimit()
                
                return try await searchForTerm(term, near: coordinate, radiusInMeters: radiusInMeters)
            } catch let error as NSError {
                lastError = error
                
                // Check for MKError throttling (error code 3)
                if error.domain == MKError.errorDomain || error.domain == "MKErrorDomain" {
                    if error.code == 3 || error.code == MKError.loadingThrottled.rawValue {
                        // Extract timeUntilReset from error info
                        var waitTime: TimeInterval = 30 // Default wait time
                        
                        if let userInfo = error.userInfo as? [String: Any] {
                            if let resetTime = userInfo["timeUntilReset"] as? Int {
                                waitTime = TimeInterval(resetTime) + 1 // Add 1 second buffer
                            }
                        }
                        
                        print("    ⏳ Rate limited for '\(term)'. Waiting \(Int(waitTime)) seconds before retry \(attempt)/\(maxRetries)...")
                        
                        // Wait for the throttle to reset
                        try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                        
                        // Reset our rate limit tracker since we waited
                        requestLock.lock()
                        requestTimestamps.removeAll()
                        requestLock.unlock()
                        
                        continue
                    }
                }
                
                // For other errors, don't retry
                throw error
            }
        }
        
        throw lastError ?? NSError(domain: "POIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"])
    }
    
    private func waitForRateLimit() async throws {
        requestLock.lock()
        
        let now = Date()
        let windowStart = now.addingTimeInterval(-windowDurationSeconds)
        
        // Remove timestamps older than the window
        requestTimestamps = requestTimestamps.filter { $0 > windowStart }
        
        // If we're at the limit, calculate wait time
        if requestTimestamps.count >= maxRequestsPerWindow - 5 { // Leave buffer of 5
            if let oldestInWindow = requestTimestamps.first {
                let waitTime = oldestInWindow.timeIntervalSince(windowStart)
                requestLock.unlock()
                
                if waitTime > 0 {
                    print("    ⏳ Proactive rate limit pause: waiting \(Int(waitTime) + 1) seconds...")
                    try? await Task.sleep(nanoseconds: UInt64((waitTime + 1) * 1_000_000_000))
                }
                
                requestLock.lock()
                // Clean up again after waiting
                let newNow = Date()
                let newWindowStart = newNow.addingTimeInterval(-windowDurationSeconds)
                requestTimestamps = requestTimestamps.filter { $0 > newWindowStart }
            }
        }
        
        // Record this request
        requestTimestamps.append(now)
        requestLock.unlock()
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
