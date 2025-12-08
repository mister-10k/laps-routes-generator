import Foundation
import CoreLocation
import MapKit

// MARK: - Supporting Types

/// Result of attempting to generate a route
enum RouteGenerationResult {
    case success(Route)
    case failedOSRM           // OSRM returned no paths or errored
    case failedForbiddenZone  // Route passed through a forbidden zone
}

struct TimeThreshold {
    let minutes: Int
    
    var minDistanceMiles: Double {
        let hours = Double(minutes) / 60.0
        return 8.0 * hours // 8 mph pace (slower = more distance needed)
    }
    
    var maxDistanceMiles: Double {
        let hours = Double(minutes) / 60.0
        return 13.0 * hours // 13 mph pace (faster = less distance needed)
    }
    
    var targetDistanceMiles: Double {
        (minDistanceMiles + maxDistanceMiles) / 2.0
    }
    
    // POI search radius is roughly half the target distance (out-and-back)
    var searchRadiusMiles: Double {
        targetDistanceMiles / 2.0
    }
    
    func isValidDistance(_ miles: Double) -> Bool {
        miles >= minDistanceMiles && miles <= maxDistanceMiles
    }
}

struct GenerationResult {
    let routes: [Route]
    let skippedThresholds: [Int] // Time thresholds that couldn't get 10 routes
    let coverageByThreshold: [Int: Int] // How many routes per threshold
}

// MARK: - Forbidden Zones (non-walkable areas)

struct ForbiddenZone {
    let name: String
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    
    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minLat &&
        coordinate.latitude <= maxLat &&
        coordinate.longitude >= minLon &&
        coordinate.longitude <= maxLon
    }
}

/// Known non-walkable areas that OSRM might incorrectly route through
let forbiddenZones: [ForbiddenZone] = [
    
    // ═══════════════════════════════════════════════════════════════════
    // NYC TUNNELS (all prohibit pedestrians)
    // ═══════════════════════════════════════════════════════════════════
    
    // Lincoln Tunnel - Midtown Manhattan to Weehawken, NJ
    ForbiddenZone(name: "Lincoln Tunnel", minLat: 40.7580, maxLat: 40.7680, minLon: -74.0300, maxLon: -73.9980),
    
    // Lincoln Tunnel Helix (spiral approach road on NJ side)
    ForbiddenZone(name: "Lincoln Tunnel Helix", minLat: 40.7650, maxLat: 40.7780, minLon: -74.0350, maxLon: -74.0150),
    
    // Holland Tunnel - Lower Manhattan to Jersey City, NJ
    ForbiddenZone(name: "Holland Tunnel", minLat: 40.7240, maxLat: 40.7340, minLon: -74.0450, maxLon: -74.0050),
    
    // Queens-Midtown Tunnel - Midtown Manhattan to Long Island City, Queens
    ForbiddenZone(name: "Queens-Midtown Tunnel", minLat: 40.7400, maxLat: 40.7520, minLon: -73.9750, maxLon: -73.9500),
    
    // Hugh L. Carey Tunnel (Brooklyn-Battery Tunnel) - Lower Manhattan to Brooklyn
    ForbiddenZone(name: "Hugh Carey Tunnel", minLat: 40.6850, maxLat: 40.7050, minLon: -74.0200, maxLon: -73.9950),
    
    // ═══════════════════════════════════════════════════════════════════
    // NYC BRIDGES WITHOUT PEDESTRIAN ACCESS
    // ═══════════════════════════════════════════════════════════════════
    
    // Verrazano-Narrows Bridge - Brooklyn to Staten Island (no pedestrians except NYC Marathon day)
    ForbiddenZone(name: "Verrazano-Narrows Bridge", minLat: 40.5950, maxLat: 40.6150, minLon: -74.0550, maxLon: -74.0300),
    
    // Throgs Neck Bridge - Bronx to Queens
    ForbiddenZone(name: "Throgs Neck Bridge", minLat: 40.7950, maxLat: 40.8150, minLon: -73.8000, maxLon: -73.7750),
    
    // Bronx-Whitestone Bridge - Bronx to Queens
    ForbiddenZone(name: "Bronx-Whitestone Bridge", minLat: 40.7950, maxLat: 40.8150, minLon: -73.8350, maxLon: -73.8100),
    
    // ═══════════════════════════════════════════════════════════════════
    // STATEN ISLAND BRIDGES TO NJ (all prohibit pedestrians)
    // ═══════════════════════════════════════════════════════════════════
    
    // Goethals Bridge - Staten Island to Elizabeth, NJ
    ForbiddenZone(name: "Goethals Bridge", minLat: 40.6300, maxLat: 40.6500, minLon: -74.2050, maxLon: -74.1800),
    
    // Bayonne Bridge - Staten Island to Bayonne, NJ
    ForbiddenZone(name: "Bayonne Bridge", minLat: 40.6350, maxLat: 40.6600, minLon: -74.1500, maxLon: -74.1250),
    
    // Outerbridge Crossing - Staten Island to Perth Amboy, NJ
    ForbiddenZone(name: "Outerbridge Crossing", minLat: 40.5200, maxLat: 40.5350, minLon: -74.2550, maxLon: -74.2350),
    
    // ═══════════════════════════════════════════════════════════════════
    // NYC EXPRESSWAYS/HIGHWAYS (limited access, no pedestrians)
    // ═══════════════════════════════════════════════════════════════════
    
    // FDR Drive - East side of Manhattan (elevated highway sections)
    // Note: Only including tunnel/underpass sections where pedestrians definitely can't go
    ForbiddenZone(name: "FDR Drive Tunnel (East 42nd)", minLat: 40.7480, maxLat: 40.7550, minLon: -73.9720, maxLon: -73.9670),
    
    // West Side Highway / Joe DiMaggio Highway - tunnel sections
    ForbiddenZone(name: "West Side Highway Tunnel", minLat: 40.7550, maxLat: 40.7650, minLon: -74.0100, maxLon: -74.0000),
]

// MARK: - RouteGenerator

class RouteGenerator {
    static let shared = RouteGenerator()
    
    // Target: 10 unique routes per time threshold
    private let routesPerThreshold = 10
    
    // All time thresholds (5, 10, 15, ... 120 minutes)
    private let allThresholds: [TimeThreshold] = stride(from: 5, through: 120, by: 5).map { TimeThreshold(minutes: $0) }
    
    // Callback for progress updates
    var onProgressUpdate: ((String) -> Void)?
    
    // Callback for when a new route is generated (for incremental UI updates)
    var onRouteGenerated: ((Route) -> Void)?
    
    // Callback to save all routes incrementally (for persistence during generation)
    var onSaveRoutes: (([Route]) -> Void)?
    
    // MARK: - Main Generation Method
    
    func generateRoutes(for city: City, startingPoint: StartingPoint, directionPreference: DirectionPreference = .noPreference, existingRoutes: [Route] = [], blacklistedPOINames: Set<String> = []) async -> GenerationResult {
        let generationStartTime = Date()
        
        print("\n╔════════════════════════════════════════════════════════════╗")
        print("║  ROUTE GENERATION STARTING                                  ║")
        print("║  City: \(city.name.padding(toLength: 48, withPad: " ", startingAt: 0))  ║")
        print("║  Starting Point: \(startingPoint.name.padding(toLength: 39, withPad: " ", startingAt: 0))  ║")
        print("║  Direction: \(directionPreference.rawValue.padding(toLength: 44, withPad: " ", startingAt: 0))  ║")
        print("║  Target: \(routesPerThreshold) unique routes per time threshold               ║")
        print("║  Thresholds: 5, 10, 15 ... 120 min (\(allThresholds.count) total)             ║")
        print("║  Existing routes to keep: \(String(existingRoutes.count).padding(toLength: 29, withPad: " ", startingAt: 0))  ║")
        print("║  Blacklisted POIs: \(String(blacklistedPOINames.count).padding(toLength: 36, withPad: " ", startingAt: 0))  ║")
        print("╚════════════════════════════════════════════════════════════╝\n")
        
        // Start with existing routes
        var allRoutes: [Route] = existingRoutes
        var usedTurnaroundPointNames: Set<String> = Set(existingRoutes.map { $0.turnaroundPoint.name }) // Track POIs already used BY NAME to prevent duplicates
        var skippedThresholds: [Int] = []
        
        let startPoint = PointOfInterest(name: startingPoint.name, coordinate: startingPoint.coordinate, type: "landmark")
        print("Starting point: \(startPoint.name) at (\(String(format: "%.4f", startingPoint.coordinate.latitude)), \(String(format: "%.4f", startingPoint.coordinate.longitude)))")
        print("Starting with \(existingRoutes.count) existing routes, \(usedTurnaroundPointNames.count) POIs already used, \(blacklistedPOINames.count) blacklisted\n")
        
        // Process thresholds in order
        for threshold in allThresholds {
            print("\n────────────────────────────────────────────────────────────")
            print("THRESHOLD: \(threshold.minutes) min | Total routes so far: \(allRoutes.count) | Used POIs: \(usedTurnaroundPointNames.count)")
            print("────────────────────────────────────────────────────────────")
            
            await updateProgress("Processing \(threshold.minutes) min threshold...")
            
            // Count how many routes we already have for this threshold
            let existingCount = allRoutes.filter { threshold.isValidDistance($0.totalDistanceMiles) }.count
            
            if existingCount >= routesPerThreshold {
                print("✓ Already satisfied! \(existingCount) existing routes work for \(threshold.minutes) min")
                continue
            }
            
            let neededCount = routesPerThreshold - existingCount
            print("→ Need \(neededCount) more routes (have \(existingCount) from previous thresholds)")
            
            // Fetch POIs at the appropriate radius
            let radiusMeters = threshold.searchRadiusMiles * 1609.34
            
            do {
                print("  Searching for POIs at radius \(String(format: "%.2f", radiusMeters)) m (\(String(format: "%.2f", threshold.searchRadiusMiles)) mi)...")
                
                let pois = try await POIService.shared.fetchPOIs(near: startingPoint.coordinate, radiusInMeters: radiusMeters)
                print("  POI search returned \(pois.count) total POIs")
                
                // Filter out POIs we've already used (by name to prevent duplicates like "Central Park" appearing multiple times)
                let unusedPOIs = pois.filter { !usedTurnaroundPointNames.contains($0.name) }
                let alreadyUsedCount = pois.count - unusedPOIs.count
                print("  After removing already-used: \(unusedPOIs.count) remaining (\(alreadyUsedCount) already used)")
                
                // Filter out manually blacklisted POIs
                let nonBlacklistedPOIs = unusedPOIs.filter { !blacklistedPOINames.contains($0.name) }
                let blacklistedCount = unusedPOIs.count - nonBlacklistedPOIs.count
                if blacklistedCount > 0 {
                    print("  After removing manually blacklisted: \(nonBlacklistedPOIs.count) remaining (\(blacklistedCount) blacklisted)")
                }
                
                // Filter out POIs that previously failed for this specific threshold (outside range or forbidden zone)
                let thresholdBlacklist = PersistenceService.shared.getThresholdBlacklistedNames(threshold: threshold.minutes, for: city.name)
                let thresholdFilteredPOIs = nonBlacklistedPOIs.filter { !thresholdBlacklist.contains($0.name) }
                let thresholdBlacklistedCount = nonBlacklistedPOIs.count - thresholdFilteredPOIs.count
                if thresholdBlacklistedCount > 0 {
                    print("  After removing threshold-blacklisted (\(threshold.minutes) min): \(thresholdFilteredPOIs.count) remaining (\(thresholdBlacklistedCount) previously failed)")
                }
                
                // Filter POIs by straight-line distance to estimate if they'll produce valid routes
                // Roads are typically 1.3-1.6x longer than straight-line, so:
                // - For a target round-trip of X miles, each leg is X/2 miles
                // - Straight-line distance should be roughly (X/2) / 1.4 = X/2.8
                // - Allow some tolerance: min = targetDistance/4, max = targetDistance/1.5
                let startLoc = CLLocation(latitude: startingPoint.coordinate.latitude, longitude: startingPoint.coordinate.longitude)
                let minStraightLineMeters = (threshold.minDistanceMiles / 4.0) * 1609.34  // Very conservative min
                let maxStraightLineMeters = (threshold.maxDistanceMiles / 1.5) * 1609.34  // Account for winding roads
                
                let availablePOIs = thresholdFilteredPOIs.filter { poi in
                    let poiLoc = CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude)
                    let straightLineDistance = poiLoc.distance(from: startLoc)
                    // Must be at least 500m away AND within our estimated useful range
                    return straightLineDistance >= 500 && 
                           straightLineDistance >= minStraightLineMeters && 
                           straightLineDistance <= maxStraightLineMeters
                }
                
                let filteredOutCount = thresholdFilteredPOIs.count - availablePOIs.count
                print("  After distance filtering: \(availablePOIs.count) POIs in straight-line range \(String(format: "%.2f", minStraightLineMeters/1609.34))-\(String(format: "%.2f", maxStraightLineMeters/1609.34)) mi (\(filteredOutCount) filtered out)")
                
                // Filter by direction preference
                let directionFilteredPOIs: [PointOfInterest]
                if directionPreference != .noPreference {
                    directionFilteredPOIs = availablePOIs.filter { poi in
                        let bearing = calculateBearing(from: startingPoint.coordinate, to: poi.coordinate)
                        return matchesDirection(bearing, preference: directionPreference)
                    }
                    let directionFilteredCount = availablePOIs.count - directionFilteredPOIs.count
                    print("  After direction filtering (\(directionPreference.rawValue)): \(directionFilteredPOIs.count) POIs (\(directionFilteredCount) filtered out)")
                } else {
                    directionFilteredPOIs = availablePOIs
                }
                
                print("  Target route distance: \(String(format: "%.2f", threshold.targetDistanceMiles)) mi | Valid range: \(String(format: "%.2f", threshold.minDistanceMiles))-\(String(format: "%.2f", threshold.maxDistanceMiles)) mi")
                
                var generatedForThreshold = 0
                var attemptedCount = 0
                var failedOSRM = 0
                var failedForbiddenZone = 0
                var outsideRange = 0
                var consecutiveOutsideRange = 0
                let maxConsecutiveOutsideRange = 20
                
                // Sort by priority (famous/popular places first) with shuffle within each tier for variety
                let prioritizedPOIs = directionFilteredPOIs
                    .sorted { $0.priority < $1.priority }
                    .chunkedByPriority()
                    .flatMap { $0.shuffled() }
                print("  Starting to iterate through \(prioritizedPOIs.count) POIs (sorted by importance)...")
                
                for poi in prioritizedPOIs {
                    // Recheck current coverage (new routes might have been added that satisfy this threshold)
                    let currentCount = allRoutes.filter { threshold.isValidDistance($0.totalDistanceMiles) }.count
                    if currentCount >= routesPerThreshold {
                        print("  ✓ COMPLETE [\(currentCount)/\(routesPerThreshold)] Threshold \(threshold.minutes) min satisfied (tried \(attemptedCount) POIs)")
                        break
                    }
                    
                    // Check if we've had too many consecutive outside-range results
                    if consecutiveOutsideRange >= maxConsecutiveOutsideRange {
                        print("  ⚠ SKIPPING [\(currentCount)/\(routesPerThreshold)]: \(maxConsecutiveOutsideRange) consecutive outside-range - POIs don't match target distance")
                        break
                    }
                    
                    attemptedCount += 1
                    
                    // Try to generate a route to this POI
                    print("    [\(attemptedCount)] [\(currentCount)/\(routesPerThreshold)] Trying: \(poi.name)...")
                    
                    let result = await generateRoute(from: startPoint, to: poi, targetDistance: threshold.targetDistanceMiles)
                    
                    switch result {
                    case .success(let route):
                        // Verify the route actually works for this threshold
                        if threshold.isValidDistance(route.totalDistanceMiles) {
                            allRoutes.append(route)
                            usedTurnaroundPointNames.insert(poi.name)
                            generatedForThreshold += 1
                            consecutiveOutsideRange = 0 // Reset on success
                            let newCount = currentCount + 1
                            print("    [\(attemptedCount)] ✓ SUCCESS [\(newCount)/\(routesPerThreshold)]: \(poi.name) → \(String(format: "%.2f", route.totalDistanceMiles)) mi")
                            
                            // Notify UI immediately
                            await notifyRouteGenerated(route)
                            
                            // Save to storage immediately so progress persists if app closes
                            await saveRoutesIncrementally(allRoutes)
                        } else {
                            outsideRange += 1
                            consecutiveOutsideRange += 1
                            // Blacklist this POI for this specific threshold - it won't produce valid distance
                            PersistenceService.shared.addToThresholdBlacklist(poiName: poi.name, threshold: threshold.minutes, for: city.name)
                            print("    [\(attemptedCount)] ✗ OUTSIDE RANGE [\(currentCount)/\(routesPerThreshold)] (\(consecutiveOutsideRange)/\(maxConsecutiveOutsideRange)): \(poi.name) → \(String(format: "%.2f", route.totalDistanceMiles)) mi (need \(String(format: "%.2f", threshold.minDistanceMiles))-\(String(format: "%.2f", threshold.maxDistanceMiles)) mi) [blacklisted for \(threshold.minutes)min]")
                        }
                        
                    case .failedOSRM:
                        failedOSRM += 1
                        // Don't count OSRM failures toward consecutive outside-range
                        // Don't blacklist - OSRM might work next time (network issue, etc.)
                        print("    [\(attemptedCount)] ✗ OSRM FAILED [\(currentCount)/\(routesPerThreshold)]: \(poi.name)")
                        
                    case .failedForbiddenZone:
                        failedForbiddenZone += 1
                        // Don't count forbidden zone failures toward consecutive outside-range
                        // Blacklist this POI for this specific threshold - path goes through forbidden zone
                        PersistenceService.shared.addToThresholdBlacklist(poiName: poi.name, threshold: threshold.minutes, for: city.name)
                        print("    [\(attemptedCount)] ✗ FORBIDDEN ZONE [\(currentCount)/\(routesPerThreshold)]: \(poi.name) [blacklisted for \(threshold.minutes)min]")
                    }
                }
                
                print("  Summary for \(threshold.minutes) min: attempted=\(attemptedCount), success=\(generatedForThreshold), outsideRange=\(outsideRange), osrmFailed=\(failedOSRM), forbiddenZone=\(failedForbiddenZone)")
                
                // Final check: did we get enough?
                let finalCount = allRoutes.filter { threshold.isValidDistance($0.totalDistanceMiles) }.count
                if finalCount < routesPerThreshold {
                    print("  ⚠ Threshold \(threshold.minutes) min only has \(finalCount) routes (need \(routesPerThreshold))")
                    if finalCount == 0 {
                        skippedThresholds.append(threshold.minutes)
                    }
                }
                
            } catch {
                print("  ✗ Error fetching POIs for \(threshold.minutes) min: \(error)")
                skippedThresholds.append(threshold.minutes)
            }
        }
        
        // Calculate final coverage
        var coverageByThreshold: [Int: Int] = [:]
        for threshold in allThresholds {
            let count = allRoutes.filter { threshold.isValidDistance($0.totalDistanceMiles) }.count
            coverageByThreshold[threshold.minutes] = count
        }
        
        // Recalculate valid session times for all routes
        let finalRoutes = allRoutes.map { route in
            let validTimes = calculateValidSessionTimes(distanceMiles: route.totalDistanceMiles)
            return Route(
                id: route.id,
                name: route.name,
                startingPoint: route.startingPoint,
                turnaroundPoint: route.turnaroundPoint,
                totalDistanceMiles: route.totalDistanceMiles,
                distanceBandMiles: route.distanceBandMiles,
                outboundPath: route.outboundPath,
                returnPath: route.returnPath,
                pacingInstructions: route.pacingInstructions,
                validSessionTimes: validTimes
            )
        }
        
        let generationDuration = Date().timeIntervalSince(generationStartTime)
        let minutes = Int(generationDuration) / 60
        let seconds = Int(generationDuration) % 60
        
        await updateProgress("Generated \(finalRoutes.count) routes")
        
        print("\n════════════════════════════════════════════════════════════")
        print("GENERATION COMPLETE")
        print("Total routes: \(finalRoutes.count) | Duration: \(minutes)m \(seconds)s")
        print("════════════════════════════════════════════════════════════")
        
        // Log summary
        logCoverageSummary(coverageByThreshold: coverageByThreshold, skippedThresholds: skippedThresholds)
        
        return GenerationResult(
            routes: finalRoutes,
            skippedThresholds: skippedThresholds,
            coverageByThreshold: coverageByThreshold
        )
    }
    
    // MARK: - Regenerate Single Route
    
    func regenerateRoute(oldRoute: Route, city: City, startingPoint: StartingPoint, directionPreference: DirectionPreference = .noPreference) async -> Route? {
        // Find which time thresholds this route serves
        guard let primaryThreshold = allThresholds.first(where: { $0.isValidDistance(oldRoute.totalDistanceMiles) }) else {
            print("Could not find matching threshold for route distance \(oldRoute.totalDistanceMiles)")
            return nil
        }
        
        print("Regenerating route for \(primaryThreshold.minutes) min threshold")
        
        let radiusMeters = primaryThreshold.searchRadiusMiles * 1609.34
        
        do {
            let pois = try await POIService.shared.fetchPOIs(near: startingPoint.coordinate, radiusInMeters: radiusMeters)
            
            // Filter out the current POI and those too close to start
            let startLoc = CLLocation(latitude: startingPoint.coordinate.latitude, longitude: startingPoint.coordinate.longitude)
            var candidates = pois.filter { poi in
                if poi.id == oldRoute.turnaroundPoint.id { return false }
                let poiLoc = CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude)
                return poiLoc.distance(from: startLoc) >= 500
            }
            
            // Apply direction filter if specified
            if directionPreference != .noPreference {
                candidates = candidates.filter { poi in
                    let bearing = calculateBearing(from: startingPoint.coordinate, to: poi.coordinate)
                    return matchesDirection(bearing, preference: directionPreference)
                }
            }
            
            let candidates_shuffled = candidates.shuffled()
            
            let startPoint = PointOfInterest(name: startingPoint.name, coordinate: startingPoint.coordinate, type: "landmark")
            
            // Try up to 10 candidates
            for poi in candidates_shuffled.prefix(10) {
                let result = await generateRoute(from: startPoint, to: poi, targetDistance: primaryThreshold.targetDistanceMiles)
                if case .success(let newRoute) = result {
                    if primaryThreshold.isValidDistance(newRoute.totalDistanceMiles) {
                        return newRoute
                    }
                }
            }
        } catch {
            print("Regenerate failed: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Private Methods
    
    /// Calculate bearing (direction) from start to end in degrees (0-360)
    /// 0/360 = North, 90 = East, 180 = South, 270 = West
    private func calculateBearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        
        // Normalize to 0-360
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
    
    /// Check if a bearing matches the desired direction preference
    private func matchesDirection(_ bearing: Double, preference: DirectionPreference) -> Bool {
        switch preference {
        case .noPreference:
            return true
        case .north:
            return bearing >= 315 || bearing <= 45  // 315-45 degrees
        case .east:
            return bearing >= 45 && bearing <= 135  // 45-135 degrees
        case .south:
            return bearing >= 135 && bearing <= 225 // 135-225 degrees
        case .west:
            return bearing >= 225 && bearing <= 315 // 225-315 degrees
        }
    }
    
    private func generateRoute(from start: PointOfInterest, to turnaroundPoint: PointOfInterest, targetDistance: Double) async -> RouteGenerationResult {
        do {
            print("        → Calling OSRM for outbound & return paths...")
            
            async let outboundTask = OSRMService.shared.fetchRoutes(from: start.coordinate, to: turnaroundPoint.coordinate)
            async let returnTask = OSRMService.shared.fetchRoutes(from: turnaroundPoint.coordinate, to: start.coordinate)
            
            let (outboundOpts, returnOpts) = try await (outboundTask, returnTask)
            
            print("        → OSRM returned \(outboundOpts.count) outbound options, \(returnOpts.count) return options")
            
            if outboundOpts.isEmpty || returnOpts.isEmpty {
                print("        → No route options from OSRM")
                return .failedOSRM
            }
            
            // Find best pair with least overlap
            var bestPair: (OSRMPath, OSRMPath)?
            var minOverlap = 1.0
            
            for outPath in outboundOpts {
                for retPath in returnOpts {
                    let overlap = OverlapCalculator.shared.calculateOverlap(pathA: outPath.coordinates, pathB: retPath.coordinates)
                    
                    if overlap < minOverlap {
                        minOverlap = overlap
                        bestPair = (outPath, retPath)
                    }
                }
            }
            
            guard let (bestOut, bestRet) = bestPair else {
                print("        → Could not find valid path pair")
                return .failedOSRM
            }
            
            let totalDistanceMeters = bestOut.distanceMeters + bestRet.distanceMeters
            let totalDistanceMiles = totalDistanceMeters / 1609.34
            
            print("        → Best pair: outbound=\(String(format: "%.2f", bestOut.distanceMeters/1609.34)) mi, return=\(String(format: "%.2f", bestRet.distanceMeters/1609.34)) mi, total=\(String(format: "%.2f", totalDistanceMiles)) mi, overlap=\(String(format: "%.0f", minOverlap * 100))%")
            
            // Check for forbidden zones (tunnels, highways, etc.)
            let allCoordinates = bestOut.coordinates + bestRet.coordinates
            if let forbiddenZone = checkForForbiddenZones(coordinates: allCoordinates) {
                print("        → ⛔ REJECTED: Route passes through \(forbiddenZone)")
                return .failedForbiddenZone
            }
            
            // Generate metadata
            let validTimes = calculateValidSessionTimes(distanceMiles: totalDistanceMiles)
            let pacing = generatePacing(distanceMiles: totalDistanceMiles)
            
            // Infer distance band for backwards compatibility
            let distanceBand = inferDistanceBand(from: totalDistanceMiles)
            
            let route = Route(
                name: turnaroundPoint.name,
                startingPoint: start,
                turnaroundPoint: turnaroundPoint,
                totalDistanceMiles: totalDistanceMiles,
                distanceBandMiles: distanceBand,
                outboundPath: bestOut.coordinates,
                returnPath: bestRet.coordinates,
                pacingInstructions: pacing,
                validSessionTimes: validTimes
            )
            
            return .success(route)
            
        } catch {
            print("        → OSRM error for \(turnaroundPoint.name): \(error)")
            return .failedOSRM
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
        var instructions: [PacingInstruction] = []
        let segments = 5
        let segmentDist = distanceMiles / Double(segments)
        
        for i in 0..<segments {
            let dist = Double(i) * segmentDist
            let speed: Double
            if i == 0 || i == segments - 1 {
                speed = 9.0
            } else {
                speed = Double.random(in: 8.5...11.0)
            }
            instructions.append(PacingInstruction(distance: dist, speed: speed))
        }
        return instructions
    }
    
    private func inferDistanceBand(from distance: Double) -> Double {
        let bands: [Double] = [1.0, 2.0, 4.0, 7.5, 9.5, 13.0, 16.0]
        return bands.min(by: { abs($0 - distance) < abs($1 - distance) }) ?? 4.0
    }
    
    /// Check if any coordinates pass through forbidden zones (tunnels, highways, etc.)
    /// Returns the name of the forbidden zone if found, nil otherwise
    private func checkForForbiddenZones(coordinates: [CLLocationCoordinate2D]) -> String? {
        for coord in coordinates {
            for zone in forbiddenZones {
                if zone.contains(coordinate: coord) {
                    return zone.name
                }
            }
        }
        return nil
    }
    
    @MainActor
    private func updateProgress(_ message: String) {
        onProgressUpdate?(message)
    }
    
    @MainActor
    private func notifyRouteGenerated(_ route: Route) {
        onRouteGenerated?(route)
    }
    
    @MainActor
    private func saveRoutesIncrementally(_ routes: [Route]) {
        onSaveRoutes?(routes)
    }
    
    private func logCoverageSummary(coverageByThreshold: [Int: Int], skippedThresholds: [Int]) {
        print("\n===== COVERAGE SUMMARY =====")
        
        let sortedThresholds = coverageByThreshold.keys.sorted()
        var fullyCovered = 0
        var partiallyCovered = 0
        
        for threshold in sortedThresholds {
            let count = coverageByThreshold[threshold] ?? 0
            let status: String
            if count >= routesPerThreshold {
                status = "✓"
                fullyCovered += 1
            } else if count > 0 {
                status = "⚠"
                partiallyCovered += 1
            } else {
                status = "✗"
            }
            print("  \(threshold) min: \(count) routes \(status)")
        }
        
        print("\nFully covered (10+): \(fullyCovered)/\(sortedThresholds.count)")
        print("Partially covered: \(partiallyCovered)")
        
        if !skippedThresholds.isEmpty {
            print("Skipped (0 routes): \(skippedThresholds.map { "\($0) min" }.joined(separator: ", "))")
        }
        print("============================\n")
    }
}

// MARK: - Array Extension for Priority Grouping

extension Array where Element == PointOfInterest {
    /// Groups POIs by their priority level, maintaining order within groups
    func chunkedByPriority() -> [[PointOfInterest]] {
        var result: [[PointOfInterest]] = []
        var currentGroup: [PointOfInterest] = []
        var currentPriority: Int?
        
        for poi in self {
            if poi.priority == currentPriority {
                currentGroup.append(poi)
            } else {
                if !currentGroup.isEmpty {
                    result.append(currentGroup)
                }
                currentGroup = [poi]
                currentPriority = poi.priority
            }
        }
        
        if !currentGroup.isEmpty {
            result.append(currentGroup)
        }
        
        return result
    }
}
