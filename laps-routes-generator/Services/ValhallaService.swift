import Foundation
import CoreLocation

// MARK: - Error Types

enum ValhallaError: Error, LocalizedError {
    case serverUnavailable(statusCode: Int, message: String)
    case rateLimited
    case invalidResponse(message: String)
    case noRouteFound
    case apiError(code: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .serverUnavailable(let statusCode, let message):
            return "Server unavailable (HTTP \(statusCode)): \(message)"
        case .rateLimited:
            return "Rate limited by Valhalla server"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .noRouteFound:
            return "No route found"
        case .apiError(let code, let message):
            return "Valhalla API error \(code): \(message)"
        }
    }
}

// Valhalla response models
private struct ValhallaResponse: Codable {
    let trip: ValhallaTrip?
    let alternates: [ValhallaAlternate]? // Alternative routes
    let error_code: Int?
    let error: String?
    let status_message: String?
}

private struct ValhallaAlternate: Codable {
    let trip: ValhallaTrip
}

private struct ValhallaTrip: Codable {
    let legs: [ValhallaLeg]
    let summary: ValhallaSummary
}

private struct ValhallaLeg: Codable {
    let shape: String
}

private struct ValhallaSummary: Codable {
    let length: Double // in kilometers
}

class ValhallaService {
    static let shared = ValhallaService()
    
    // Multiple Valhalla servers for fallback
    private let valhallaServers = [
        "https://valhalla1.openstreetmap.de/route",
        "https://valhalla2.openstreetmap.de/route"
    ]
    
    // Retry configuration
    private let maxRetries = 3
    private let retryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    
    func fetchRoutes(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> [OSRMPath] {
        var lastError: Error?
        
        // Try each server with retries
        for (serverIndex, baseURL) in valhallaServers.enumerated() {
            for attempt in 1...maxRetries {
                do {
                    return try await fetchRoutesFromServer(baseURL: baseURL, from: start, to: end)
                } catch let error as ValhallaError {
                    lastError = error
                    
                    switch error {
                    case .rateLimited, .serverUnavailable:
                        // Wait before retrying or trying next server
                        if attempt < maxRetries {
                            try? await Task.sleep(nanoseconds: retryDelay * UInt64(attempt))
                        }
                    case .noRouteFound, .apiError:
                        // Don't retry for these errors - they won't change
                        throw error
                    case .invalidResponse:
                        // Could be transient, try again
                        if attempt < maxRetries {
                            try? await Task.sleep(nanoseconds: retryDelay)
                        }
                    }
                } catch {
                    lastError = error
                    // Network error - try again
                    if attempt < maxRetries {
                        try? await Task.sleep(nanoseconds: retryDelay)
                    }
                }
            }
            
            // If we've exhausted retries on this server, try next one
            if serverIndex < valhallaServers.count - 1 {
                // Small delay before trying next server
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
        
        // All servers and retries exhausted, try OSRM as fallback
        do {
            let osrmPaths = try await OSRMService.shared.fetchRoutes(from: start, to: end)
            if !osrmPaths.isEmpty {
                return osrmPaths
            }
        } catch {
            // OSRM also failed, throw the original Valhalla error
        }
        
        throw lastError ?? ValhallaError.noRouteFound
    }
    
    private func fetchRoutesFromServer(baseURL: String, from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> [OSRMPath] {
        // Build the JSON request for Valhalla with alternatives
        // Using bicycle costing - prefers roads, avoids frequent turns, still avoids highways
        let requestJSON: [String: Any] = [
            "locations": [
                ["lat": start.latitude, "lon": start.longitude],
                ["lat": end.latitude, "lon": end.longitude]
            ],
            "costing": "bicycle",
            "costing_options": [
                "bicycle": [
                    "bicycle_type": "Road",      // Road bike - prefers smooth roads
                    "use_roads": 0.9,            // Strongly prefer roads
                    "use_hills": 0.3,            // Avoid hills somewhat
                    "maneuver_penalty": 30       // Penalize each turn - encourages longer straight segments
                ]
            ],
            "alternates": 3, // Request up to 3 alternative routes for variety
            "directions_options": [
                "units": "kilometers"
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestJSON),
              let jsonString = String(data: jsonData, encoding: .utf8),
              let encodedJSON = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)?json=\(encodedJSON)") else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Check HTTP status code first
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299:
                break // Success, continue processing
            case 429:
                throw ValhallaError.rateLimited
            case 500...599:
                let message = String(data: data, encoding: .utf8) ?? "Server error"
                throw ValhallaError.serverUnavailable(statusCode: httpResponse.statusCode, message: message)
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ValhallaError.serverUnavailable(statusCode: httpResponse.statusCode, message: message)
            }
        }
        
        // Check if response is HTML (error page) instead of JSON
        if let responseString = String(data: data, encoding: .utf8),
           responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            // Got HTML instead of JSON - server returned an error page
            throw ValhallaError.invalidResponse(message: "Server returned HTML instead of JSON")
        }
        
        let valhallaResponse: ValhallaResponse
        do {
            valhallaResponse = try JSONDecoder().decode(ValhallaResponse.self, from: data)
        } catch {
            throw ValhallaError.invalidResponse(message: "Failed to decode JSON: \(error.localizedDescription)")
        }
        
        // Check for API errors
        if let errorCode = valhallaResponse.error_code, let errorMessage = valhallaResponse.error ?? valhallaResponse.status_message {
            throw ValhallaError.apiError(code: errorCode, message: errorMessage)
        }
        
        var paths: [OSRMPath] = []
        
        // Add the main trip
        if let trip = valhallaResponse.trip, let firstLeg = trip.legs.first {
            let coordinates = decodePolyline6(firstLeg.shape)
            let distanceMeters = trip.summary.length * 1000
            paths.append(OSRMPath(coordinates: coordinates, distanceMeters: distanceMeters))
        }
        
        // Add any alternatives
        if let alternates = valhallaResponse.alternates {
            for alternate in alternates {
                if let firstLeg = alternate.trip.legs.first {
                    let coordinates = decodePolyline6(firstLeg.shape)
                    let distanceMeters = alternate.trip.summary.length * 1000
                    paths.append(OSRMPath(coordinates: coordinates, distanceMeters: distanceMeters))
                }
            }
        }
        
        if paths.isEmpty {
            throw ValhallaError.noRouteFound
        }
        
        return paths
    }
    
    // MARK: - Polyline6 Decoding
    
    /// Valhalla uses polyline6 encoding (precision 6, unlike Google's precision 5)
    private func decodePolyline6(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var lat = 0
        var lng = 0
        
        while index < encoded.endIndex {
            // Decode latitude
            var shift = 0
            var result = 0
            var byte: Int
            
            repeat {
                guard index < encoded.endIndex,
                      let asciiValue = encoded[index].asciiValue else { break }
                byte = Int(asciiValue) - 63
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            
            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat
            
            // Decode longitude
            shift = 0
            result = 0
            
            repeat {
                guard index < encoded.endIndex,
                      let asciiValue = encoded[index].asciiValue else { break }
                byte = Int(asciiValue) - 63
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            
            let deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += deltaLng
            
            // Polyline6 uses precision 6 (divide by 1e6)
            coordinates.append(CLLocationCoordinate2D(
                latitude: Double(lat) / 1e6,
                longitude: Double(lng) / 1e6
            ))
        }
        
        return coordinates
    }
}

