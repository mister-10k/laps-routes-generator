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
    let startingPoint: PointOfInterest
    let midpoint: PointOfInterest
    let totalDistanceMiles: Double
    let distanceBandMiles: Double // Target distance band (1.0, 2.0, 4.0, etc.)
    private let outboundPathEncoded: [CodableCoordinate]
    private let returnPathEncoded: [CodableCoordinate]
    let pacingInstructions: [PacingInstruction]
    let validSessionTimes: [Int]
    
    var outboundPath: [CLLocationCoordinate2D] {
        outboundPathEncoded.map { $0.clCoordinate }
    }
    
    var returnPath: [CLLocationCoordinate2D] {
        returnPathEncoded.map { $0.clCoordinate }
    }
    
    // MARK: - Coding Keys
    
    private enum CodingKeys: String, CodingKey {
        case id, name, startingPoint, midpoint, totalDistanceMiles, distanceBandMiles
        case outboundPathEncoded, returnPathEncoded, pacingInstructions, validSessionTimes
    }
    
    // MARK: - Custom Decoder (backwards compatibility)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startingPoint = try container.decode(PointOfInterest.self, forKey: .startingPoint)
        midpoint = try container.decode(PointOfInterest.self, forKey: .midpoint)
        totalDistanceMiles = try container.decode(Double.self, forKey: .totalDistanceMiles)
        outboundPathEncoded = try container.decode([CodableCoordinate].self, forKey: .outboundPathEncoded)
        returnPathEncoded = try container.decode([CodableCoordinate].self, forKey: .returnPathEncoded)
        pacingInstructions = try container.decode([PacingInstruction].self, forKey: .pacingInstructions)
        validSessionTimes = try container.decode([Int].self, forKey: .validSessionTimes)
        
        // Backwards compatibility: infer distance band from total distance if not present
        if let band = try container.decodeIfPresent(Double.self, forKey: .distanceBandMiles) {
            distanceBandMiles = band
        } else {
            distanceBandMiles = Route.inferDistanceBand(from: totalDistanceMiles)
        }
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        name: String,
        startingPoint: PointOfInterest,
        midpoint: PointOfInterest,
        totalDistanceMiles: Double,
        distanceBandMiles: Double,
        outboundPath: [CLLocationCoordinate2D],
        returnPath: [CLLocationCoordinate2D],
        pacingInstructions: [PacingInstruction],
        validSessionTimes: [Int]
    ) {
        self.id = id
        self.name = name
        self.startingPoint = startingPoint
        self.midpoint = midpoint
        self.totalDistanceMiles = totalDistanceMiles
        self.distanceBandMiles = distanceBandMiles
        self.outboundPathEncoded = outboundPath.map { CodableCoordinate($0) }
        self.returnPathEncoded = returnPath.map { CodableCoordinate($0) }
        self.pacingInstructions = pacingInstructions
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
