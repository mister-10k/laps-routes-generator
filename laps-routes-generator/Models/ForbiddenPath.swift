import Foundation
import CoreLocation

/// A forbidden path segment that should not be used in generated routes.
/// Stored as a series of coordinates that define the path to avoid.
struct ForbiddenPath: Identifiable, Codable, Equatable {
    let id: UUID
    let coordinates: [Coordinate]
    let createdAt: Date
    
    /// Simple coordinate struct for Codable conformance
    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double
        
        init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
        
        init(from clCoordinate: CLLocationCoordinate2D) {
            self.latitude = clCoordinate.latitude
            self.longitude = clCoordinate.longitude
        }
        
        var clCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    
    init(id: UUID = UUID(), coordinates: [CLLocationCoordinate2D], createdAt: Date = Date()) {
        self.id = id
        self.coordinates = coordinates.map { Coordinate(from: $0) }
        self.createdAt = createdAt
    }
    
    /// Get coordinates as CLLocationCoordinate2D array
    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { $0.clCoordinate }
    }
    
    /// Check if a route actually TRAVELS ALONG this forbidden path (not just crosses it).
    /// 
    /// The key distinction:
    /// - CROSSING (allowed): Route briefly passes through the forbidden area (1-2 points)
    ///   This happens when walking under/over a highway via underpass or overpass.
    /// - TRAVELING (forbidden): Route follows the forbidden path for a significant distance
    ///   This happens when actually walking on the highway.
    ///
    /// Detection: Only triggers if 3+ consecutive route points are near the forbidden path
    /// AND those points travel at least 50 meters along it.
    func containsSegment(_ routeCoordinates: [CLLocationCoordinate2D], threshold: Double = 25.0) -> Bool {
        guard coordinates.count >= 2, routeCoordinates.count >= 3 else { return false }
        
        // Minimum consecutive points to be considered "traveling along"
        let minConsecutivePoints = 3
        // Minimum distance traveled along the forbidden path to trigger rejection
        let minDistanceAlongPath: Double = 50.0
        
        var consecutiveCount = 0
        var distanceInZone: Double = 0.0
        var previousInZoneCoord: CLLocationCoordinate2D? = nil
        
        for routeCoord in routeCoordinates {
            let isNearForbiddenPath = isPointNearPath(routeCoord, threshold: threshold)
            
            if isNearForbiddenPath {
                // Add distance if we have a previous point also in the zone
                if let prevCoord = previousInZoneCoord {
                    let loc1 = CLLocation(latitude: prevCoord.latitude, longitude: prevCoord.longitude)
                    let loc2 = CLLocation(latitude: routeCoord.latitude, longitude: routeCoord.longitude)
                    distanceInZone += loc1.distance(from: loc2)
                }
                
                consecutiveCount += 1
                previousInZoneCoord = routeCoord
                
                // Check if we've triggered the threshold
                if consecutiveCount >= minConsecutivePoints && distanceInZone >= minDistanceAlongPath {
                    return true
                }
            } else {
                // Exited the zone - reset counters
                consecutiveCount = 0
                distanceInZone = 0.0
                previousInZoneCoord = nil
            }
        }
        
        return false
    }
    
    /// Check if a point is near any segment of the forbidden path
    private func isPointNearPath(_ point: CLLocationCoordinate2D, threshold: Double) -> Bool {
        let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
        
        // Check distance to each segment of the forbidden path
        for i in 0..<(coordinates.count - 1) {
            let segmentStart = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            let segmentEnd = CLLocation(latitude: coordinates[i + 1].latitude, longitude: coordinates[i + 1].longitude)
            
            let distance = distanceToSegment(point: pointLocation, segmentStart: segmentStart, segmentEnd: segmentEnd)
            if distance <= threshold {
                return true
            }
        }
        
        // Also check distance to individual points (for sparse paths)
        for coord in coordinates {
            let coordLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if pointLocation.distance(from: coordLocation) <= threshold {
                return true
            }
        }
        
        return false
    }
    
    /// Calculate the perpendicular distance from a point to a line segment
    private func distanceToSegment(point: CLLocation, segmentStart: CLLocation, segmentEnd: CLLocation) -> Double {
        let px = point.coordinate.latitude
        let py = point.coordinate.longitude
        let ax = segmentStart.coordinate.latitude
        let ay = segmentStart.coordinate.longitude
        let bx = segmentEnd.coordinate.latitude
        let by = segmentEnd.coordinate.longitude
        
        let abx = bx - ax
        let aby = by - ay
        let apx = px - ax
        let apy = py - ay
        
        let abSquared = abx * abx + aby * aby
        
        if abSquared == 0 {
            // Segment is a point
            return point.distance(from: segmentStart)
        }
        
        // Project point onto line, clamped to segment
        var t = (apx * abx + apy * aby) / abSquared
        t = max(0, min(1, t))
        
        let closestLat = ax + t * abx
        let closestLon = ay + t * aby
        let closestPoint = CLLocation(latitude: closestLat, longitude: closestLon)
        
        return point.distance(from: closestPoint)
    }
    
    /// Calculate the total length of this forbidden path in meters
    var lengthMeters: Double {
        guard coordinates.count > 1 else { return 0 }
        
        var total: Double = 0
        for i in 0..<(coordinates.count - 1) {
            let loc1 = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            let loc2 = CLLocation(latitude: coordinates[i + 1].latitude, longitude: coordinates[i + 1].longitude)
            total += loc1.distance(from: loc2)
        }
        return total
    }
}

