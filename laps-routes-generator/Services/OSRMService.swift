import Foundation
import CoreLocation

struct OSRMPath {
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: Double
}

private struct OSRMResponse: Codable {
    let routes: [OSRMRoute]
}

private struct OSRMRoute: Codable {
    let distance: Double
    let geometry: OSRMGeometry
}

private struct OSRMGeometry: Codable {
    let coordinates: [[Double]] // [lon, lat]
    let type: String
}

class OSRMService {
    static let shared = OSRMService()
    
    private let baseURL = "https://router.project-osrm.org/route/v1/foot"
    
    func fetchRoutes(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> [OSRMPath] {
        // Format: {startLng},{startLat};{endLng},{endLat}
        let coordinatesString = "\(start.longitude),\(start.latitude);\(end.longitude),\(end.latitude)"
        let urlString = "\(baseURL)/\(coordinatesString)?alternatives=true&geometries=geojson&overview=full"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OSRMResponse.self, from: data)
        
        return response.routes.map { route in
            let coords = route.geometry.coordinates.map { point in
                CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
            }
            return OSRMPath(coordinates: coords, distanceMeters: route.distance)
        }
    }
}

