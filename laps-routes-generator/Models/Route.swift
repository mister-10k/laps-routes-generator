import Foundation
import CoreLocation

// Helper struct for encoding coordinates
struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    
    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Route: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let continent: String
    let startingPoint: PointOfInterest
    let turnaroundPoint: PointOfInterest
    let totalDistanceMiles: Double
    let distanceBandMiles: Double // Target distance band (1.0, 2.0, 4.0, etc.)
    private let outboundPathEncoded: [CodableCoordinate]
    private let returnPathEncoded: [CodableCoordinate]
    let validSessionTimes: [Int]
    
    var outboundPath: [CLLocationCoordinate2D] {
        outboundPathEncoded.map { $0.clCoordinate }
    }
    
    var returnPath: [CLLocationCoordinate2D] {
        returnPathEncoded.map { $0.clCoordinate }
    }
    
    // MARK: - Coding Keys
    
    private enum CodingKeys: String, CodingKey {
        case id, name, continent, startingPoint, turnaroundPoint, midpoint, totalDistanceMiles, distanceBandMiles
        case outboundPathEncoded, returnPathEncoded, validSessionTimes
    }
    
    // MARK: - Custom Decoder (backwards compatibility)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        
        // Backwards compatibility: default to empty string if continent not present
        continent = try container.decodeIfPresent(String.self, forKey: .continent) ?? ""
        
        startingPoint = try container.decode(PointOfInterest.self, forKey: .startingPoint)
        
        // Backwards compatibility: try new key first, fall back to old "midpoint" key
        if let point = try container.decodeIfPresent(PointOfInterest.self, forKey: .turnaroundPoint) {
            turnaroundPoint = point
        } else {
            turnaroundPoint = try container.decode(PointOfInterest.self, forKey: .midpoint)
        }
        
        totalDistanceMiles = try container.decode(Double.self, forKey: .totalDistanceMiles)
        outboundPathEncoded = try container.decode([CodableCoordinate].self, forKey: .outboundPathEncoded)
        returnPathEncoded = try container.decode([CodableCoordinate].self, forKey: .returnPathEncoded)
        validSessionTimes = try container.decode([Int].self, forKey: .validSessionTimes)
        
        // Backwards compatibility: infer distance band from total distance if not present
        if let band = try container.decodeIfPresent(Double.self, forKey: .distanceBandMiles) {
            distanceBandMiles = band
        } else {
            distanceBandMiles = Route.inferDistanceBand(from: totalDistanceMiles)
        }
    }
    
    // MARK: - Custom Encoder (writes new key only)
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(continent, forKey: .continent)
        try container.encode(startingPoint, forKey: .startingPoint)
        try container.encode(turnaroundPoint, forKey: .turnaroundPoint)
        try container.encode(totalDistanceMiles, forKey: .totalDistanceMiles)
        try container.encode(distanceBandMiles, forKey: .distanceBandMiles)
        try container.encode(outboundPathEncoded, forKey: .outboundPathEncoded)
        try container.encode(returnPathEncoded, forKey: .returnPathEncoded)
        try container.encode(validSessionTimes, forKey: .validSessionTimes)
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        name: String,
        continent: String,
        startingPoint: PointOfInterest,
        turnaroundPoint: PointOfInterest,
        totalDistanceMiles: Double,
        distanceBandMiles: Double,
        outboundPath: [CLLocationCoordinate2D],
        returnPath: [CLLocationCoordinate2D],
        validSessionTimes: [Int]
    ) {
        self.id = id
        self.name = name
        self.continent = continent
        self.startingPoint = startingPoint
        self.turnaroundPoint = turnaroundPoint
        self.totalDistanceMiles = totalDistanceMiles
        self.distanceBandMiles = distanceBandMiles
        self.outboundPathEncoded = outboundPath.map { CodableCoordinate($0) }
        self.returnPathEncoded = returnPath.map { CodableCoordinate($0) }
        self.validSessionTimes = validSessionTimes
    }
    
    // MARK: - Helpers
    
    /// Infers the closest distance band from the actual route distance (for backwards compatibility)
    private static func inferDistanceBand(from distance: Double) -> Double {
        let bands: [Double] = [1.0, 2.0, 4.0, 7.5, 9.5, 13.0, 16.0]
        return bands.min(by: { abs($0 - distance) < abs($1 - distance) }) ?? 4.0
    }
    
    // MARK: - Hashable
    
    static func == (lhs: Route, rhs: Route) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
