import Foundation
import CoreLocation

struct SupabasePOI: Encodable {
    let id: UUID
    let name: String
    let continent: String
    let city: String
    let latitude: Double
    let longitude: Double
    let type: String
}

struct SupabaseRoute: Encodable {
    let id: UUID
    let name: String
    let starting_point_id: UUID
    let turnaround_point_id: UUID
    let total_distance_miles: Double
    let outbound_path: [[Double]] // JSONB
    let return_path: [[Double]]   // JSONB
    let valid_session_times: [Int] // Array
}

class SupabaseService {
    static let shared = SupabaseService()
    
    private let headers = [
        "apikey": SupabaseConfig.key,
        "Authorization": "Bearer \(SupabaseConfig.key)",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates" // For upsert behavior
    ]
    
    func export(city: City, routes: [Route]) async throws {
        print("\n🚀 Starting Supabase Export for \(city.name)")
        print("   Routes to export: \(routes.count)")
        
        // 1. Collect all unique POIs (starting points + turnaround points)
        // Deduplicate by name + coordinates, not by UUID (since routes generate new UUIDs each time)
        var uniquePOIsByLocation: [String: PointOfInterest] = [:]
        
        for route in routes {
            // Create a unique key based on name and rounded coordinates
            let startKey = makeLocationKey(poi: route.startingPoint)
            let turnaroundKey = makeLocationKey(poi: route.turnaroundPoint)
            
            // Only keep the first occurrence of each location
            if uniquePOIsByLocation[startKey] == nil {
                uniquePOIsByLocation[startKey] = route.startingPoint
            }
            if uniquePOIsByLocation[turnaroundKey] == nil {
                uniquePOIsByLocation[turnaroundKey] = route.turnaroundPoint
            }
        }
        
        print("   Unique POIs to upsert: \(uniquePOIsByLocation.count)")
        
        // Build a mapping from location key -> POI ID (the deduplicated one we'll actually insert)
        var locationKeyToId: [String: UUID] = [:]
        for (key, poi) in uniquePOIsByLocation {
            locationKeyToId[key] = poi.id
        }
        
        let supabasePOIs = uniquePOIsByLocation.values.map { poi in
            SupabasePOI(
                id: poi.id,
                name: poi.name,
                continent: city.continent,
                city: city.name,
                latitude: poi.latitude,
                longitude: poi.longitude,
                type: poi.type
            )
        }
        
        // 2. Upsert POIs
        try await upsertPOIs(supabasePOIs)
        
        // 3. Insert Routes (using deduplicated POI IDs)
        let supabaseRoutes = routes.map { route in
            // Look up the correct POI ID using the location key
            let startKey = makeLocationKey(poi: route.startingPoint)
            let turnaroundKey = makeLocationKey(poi: route.turnaroundPoint)
            
            let startingPointId = locationKeyToId[startKey] ?? route.startingPoint.id
            let turnaroundPointId = locationKeyToId[turnaroundKey] ?? route.turnaroundPoint.id
            
            return SupabaseRoute(
                id: route.id,
                name: route.name,
                starting_point_id: startingPointId,
                turnaround_point_id: turnaroundPointId,
                total_distance_miles: route.totalDistanceMiles,
                outbound_path: route.outboundPath.map { [$0.latitude, $0.longitude] },
                return_path: route.returnPath.map { [$0.latitude, $0.longitude] },
                valid_session_times: route.validSessionTimes.map { $0 * 60 } // Convert minutes to seconds for Laps convention
            )
        }
        
        try await insertRoutes(supabaseRoutes)
    }
    
    private func upsertPOIs(_ pois: [SupabasePOI]) async throws {
        let url = URL(string: "\(SupabaseConfig.url)/rest/v1/points_of_interest")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = try JSONEncoder().encode(pois)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("📤 POI Upsert Response: Status \(httpResponse.statusCode)")
            
            if httpResponse.statusCode >= 300 {
                // Try to parse error message from response
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Supabase POI Error Response: \(errorString)")
                }
                throw NSError(
                    domain: "SupabaseService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "POI upsert failed with status \(httpResponse.statusCode)"]
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create a unique key for a POI based on name and location
    /// This ensures we deduplicate POIs that represent the same physical location
    private func makeLocationKey(poi: PointOfInterest) -> String {
        // Round coordinates to 6 decimal places (~0.1 meters precision)
        let lat = String(format: "%.6f", poi.latitude)
        let lon = String(format: "%.6f", poi.longitude)
        return "\(poi.name)_\(lat)_\(lon)"
    }
    
    private func insertRoutes(_ routes: [SupabaseRoute]) async throws {
        // We might want to clear existing routes for this city? 
        // Or just upsert. If we use upsert, we need ID match.
        // For now, let's assume upsert is fine since IDs are stable in memory but new each run unless persisted.
        // Actually, IDs are UUID() generated in Route struct. If we re-run app, IDs change.
        // So we will insert new rows every time. 
        // Ideally we should delete old routes for this city or user manages it.
        // For MVP, just insert.
        
        let url = URL(string: "\(SupabaseConfig.url)/rest/v1/routes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = try JSONEncoder().encode(routes)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("📤 Routes Insert Response: Status \(httpResponse.statusCode)")
            
            if httpResponse.statusCode >= 300 {
                // Try to parse error message from response
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Supabase Routes Error Response: \(errorString)")
                }
                throw NSError(
                    domain: "SupabaseService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Routes insert failed with status \(httpResponse.statusCode)"]
                )
            }
        }
    }
}

