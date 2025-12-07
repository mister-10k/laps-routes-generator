import Foundation
import CoreLocation
import MapKit

struct DistanceBand {
    let targetDistanceMiles: Double
    let minRadiusMiles: Double
    let maxRadiusMiles: Double
    let countNeeded: Int
}

class RouteGenerator {
    static let shared = RouteGenerator()
    
    // MARK: - POI Query Strategy
    // Routes are generated in distance bands. For each band, we query POIs at a specific
    // radius to find suitable midpoints for out-and-back routes.
    //
    // Target Distance | Query Radius  | POI Count Needed
    // ----------------|---------------|------------------
    // ~1.0 mi         | 0.5-0.6 mi    | 10+
    // ~2.0 mi         | 0.9-1.1 mi    | 10+
    // ~4.0 mi         | 1.8-2.2 mi    | 9+
    // ~7.5 mi         | 3.5-4.0 mi    | 8+
    // ~9.5 mi         | 4.5-5.0 mi    | 4+
    // ~13.0 mi        | 6.0-7.0 mi    | 5+
    // ~16.0 mi        | 7.5-8.5 mi    | 10+
    
    private let bands: [DistanceBand] = [
        DistanceBand(targetDistanceMiles: 1.0, minRadiusMiles: 0.5, maxRadiusMiles: 0.6, countNeeded: 10),
        DistanceBand(targetDistanceMiles: 2.0, minRadiusMiles: 0.9, maxRadiusMiles: 1.1, countNeeded: 10),
        DistanceBand(targetDistanceMiles: 4.0, minRadiusMiles: 1.8, maxRadiusMiles: 2.2, countNeeded: 9),
        DistanceBand(targetDistanceMiles: 7.5, minRadiusMiles: 3.5, maxRadiusMiles: 4.0, countNeeded: 8),
        DistanceBand(targetDistanceMiles: 9.5, minRadiusMiles: 4.5, maxRadiusMiles: 5.0, countNeeded: 4),
        DistanceBand(targetDistanceMiles: 13.0, minRadiusMiles: 6.0, maxRadiusMiles: 7.0, countNeeded: 5),
        DistanceBand(targetDistanceMiles: 16.0, minRadiusMiles: 7.5, maxRadiusMiles: 8.5, countNeeded: 10)
    ]
    
    func generateRoutes(for city: City) async -> [Route] {
        var allRoutes: [Route] = []
        let startPoint = PointOfInterest(name: city.landmarkName, coordinate: city.coordinate, type: "landmark")
        
        for band in bands {
            print("Processing band: \(band.targetDistanceMiles) miles")
            // Pick a random radius within the range to vary slightly? Or just avg.
            let avgRadiusMiles = (band.minRadiusMiles + band.maxRadiusMiles) / 2.0
            let radiusMeters = avgRadiusMiles * 1609.34
            
            do {
                let pois = try await POIService.shared.fetchPOIs(near: city.coordinate, radiusInMeters: radiusMeters)
                print("Found \(pois.count) POIs for band \(band.targetDistanceMiles)")
                
                // Shuffle and pick needed count
                let candidates = pois.shuffled().prefix(band.countNeeded * 2) // Get more candidates to filter
                
                var bandRoutes: [Route] = []
                
                for poi in candidates {
                    if bandRoutes.count >= band.countNeeded { break }
                    
                    // Skip if POI is too close to start (e.g. same place)
                    let poiLoc = CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude)
                    let startLoc = CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
                    if poiLoc.distance(from: startLoc) < 500 { continue }
                    
                    if let route = await generateRoute(from: startPoint, to: poi, bandTarget: band.targetDistanceMiles) {
                        bandRoutes.append(route)
                    }
                }
                
                allRoutes.append(contentsOf: bandRoutes)
                
            } catch {
                print("Error fetching POIs for band \(band.targetDistanceMiles): \(error)")
            }
        }
        
        return allRoutes
    }
    
    func regenerateRoute(oldRoute: Route, city: City) async -> Route? {
        // Find closest band
        guard let band = bands.min(by: { abs($0.targetDistanceMiles - oldRoute.totalDistanceMiles) < abs($1.targetDistanceMiles - oldRoute.totalDistanceMiles) }) else {
            return nil
        }
        
        print("Regenerating route for band \(band.targetDistanceMiles) miles")
        
        let avgRadiusMiles = (band.minRadiusMiles + band.maxRadiusMiles) / 2.0
        let radiusMeters = avgRadiusMiles * 1609.34
        
        do {
            let pois = try await POIService.shared.fetchPOIs(near: city.coordinate, radiusInMeters: radiusMeters)
            
            // Try to find a different POI
            let candidates = pois.filter { $0.id != oldRoute.midpoint.id }.shuffled()
            
            let startPoint = oldRoute.startingPoint
            
            // Try up to 5 candidates
            for poi in candidates.prefix(5) {
                // Check min distance from start
                let poiLoc = CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude)
                let startLoc = CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
                if poiLoc.distance(from: startLoc) < 500 { continue }
                
                if let newRoute = await generateRoute(from: startPoint, to: poi, bandTarget: band.targetDistanceMiles) {
                     return newRoute
                }
            }
        } catch {
            print("Regenerate failed: \(error)")
        }
        return nil
    }
    
    private func generateRoute(from start: PointOfInterest, to midpoint: PointOfInterest, bandTarget: Double) async -> Route? {
        do {
            async let outboundTask = OSRMService.shared.fetchRoutes(from: start.coordinate, to: midpoint.coordinate)
            async let returnTask = OSRMService.shared.fetchRoutes(from: midpoint.coordinate, to: start.coordinate)
            
            let (outboundOpts, returnOpts) = try await (outboundTask, returnTask)
            
            // Find best pair with least overlap
            var bestPair: (OSRMPath, OSRMPath)?
            var minOverlap = 1.0 // 100%
            
            for outPath in outboundOpts {
                for retPath in returnOpts {
                    let overlap = OverlapCalculator.shared.calculateOverlap(pathA: outPath.coordinates, pathB: retPath.coordinates)
                    
                    // Prefer routes where total distance is close to target * 2?
                    // Actually, target distance in band is total loop distance.
                    // The POI search radius is roughly half of that.
                    // So we check if total distance is reasonable?
                    // The prompt says: "Route distance approx 2x POI distance".
                    // band.targetDistanceMiles is the route distance.
                    
                    if overlap < minOverlap {
                        minOverlap = overlap
                        bestPair = (outPath, retPath)
                    }
                }
            }
            
            guard let (bestOut, bestRet) = bestPair else { return nil }
            
            // If overlap is too high (> 50%), maybe skip? For now accept everything for MVP.
            
            let totalDistanceMeters = bestOut.distanceMeters + bestRet.distanceMeters
            let totalDistanceMiles = totalDistanceMeters / 1609.34
            
            // Generate metadata
            let validTimes = calculateValidSessionTimes(distanceMiles: totalDistanceMiles)
            let pacing = generatePacing(distanceMiles: totalDistanceMiles)
            
            return Route(
                name: "\(midpoint.name) Loop",
                startingPoint: start,
                midpoint: midpoint,
                totalDistanceMiles: totalDistanceMiles,
                distanceBandMiles: bandTarget,
                outboundPath: bestOut.coordinates,
                returnPath: bestRet.coordinates,
                pacingInstructions: pacing,
                validSessionTimes: validTimes
            )
            
        } catch {
            print("Error generating route to \(midpoint.name): \(error)")
            return nil
        }
    }
    
    private func calculateValidSessionTimes(distanceMiles: Double) -> [Int] {
        let durations = stride(from: 5, through: 120, by: 5)
        return durations.filter { duration in
            let hours = Double(duration) / 60.0
            let minDist = 8.0 * hours
            let maxDist = 13.0 * hours
            return distanceMiles >= minDist && distanceMiles <= maxDist
        }
    }
    
    private func generatePacing(distanceMiles: Double) -> [PacingInstruction] {
        // Simple template
        // Start 9.0, vary, end 9.0
        var instructions: [PacingInstruction] = []
        let segments = 5
        let segmentDist = distanceMiles / Double(segments)
        
        for i in 0..<segments {
            let dist = Double(i) * segmentDist
            let speed: Double
            if i == 0 || i == segments - 1 {
                speed = 9.0
            } else {
                // Random variation between 8.5 and 11.0
                speed = Double.random(in: 8.5...11.0)
            }
            instructions.append(PacingInstruction(distance: dist, speed: speed))
        }
        return instructions
    }
}

