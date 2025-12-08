import Foundation
import CoreLocation

struct SupabasePOI: Encodable {
    let id: UUID
    let name: String
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
    let pacing_instructions: [PacingInstruction] // JSONB
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
        // 1. Collect all unique POIs (starting points + turnaround points)
        var poisToUpsert = Set<PointOfInterest>()
        for route in routes {
            poisToUpsert.insert(route.startingPoint)
            poisToUpsert.insert(route.turnaroundPoint)
        }
        
        let supabasePOIs = poisToUpsert.map { poi in
            SupabasePOI(
                id: poi.id,
                name: poi.name,
                latitude: poi.latitude,
                longitude: poi.longitude,
                type: poi.type
            )
        }
        
        // 2. Upsert POIs
        try await upsertPOIs(supabasePOIs)
        
        // 3. Insert Routes
        let supabaseRoutes = routes.map { route in
            SupabaseRoute(
                id: route.id,
                name: route.name,
                starting_point_id: route.startingPoint.id,
                turnaround_point_id: route.turnaroundPoint.id,
                total_distance_miles: route.totalDistanceMiles,
                outbound_path: route.outboundPath.map { [$0.latitude, $0.longitude] },
                return_path: route.returnPath.map { [$0.latitude, $0.longitude] },
                pacing_instructions: route.pacingInstructions,
                valid_session_times: route.validSessionTimes
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
        
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 300 {
            throw URLError(.badServerResponse)
        }
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
        
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 300 {
            throw URLError(.badServerResponse)
        }
    }
}

