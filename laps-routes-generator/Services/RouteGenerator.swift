import Foundation
import CoreLocation
import MapKit

// MARK: - Supporting Types

/// Result of attempting to generate a route
enum RouteGenerationResult {
    case success(Route)
    case failedRouting        // Routing API returned no paths (can retry with different POI)
    case fatalAPIError(String) // API key/billing issue - stop everything immediately
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
                
                // Filter out POIs that previously failed for this specific threshold (outside range)
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
                var failedRouting = 0
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
                    
                    let result = await generateRoute(from: startPoint, to: poi, targetDistance: threshold.targetDistanceMiles, continent: city.continent)
                    
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
                        
                    case .failedRouting:
                        failedRouting += 1
                        // Don't count routing failures toward consecutive outside-range
                        // Don't blacklist - routing might work next time (network issue, etc.)
                        print("    [\(attemptedCount)] ✗ ROUTING FAILED [\(currentCount)/\(routesPerThreshold)]: \(poi.name)")
                        
                    case .fatalAPIError(let message):
                        // STOP EVERYTHING - API key or billing issue
                        print("\n🛑🛑🛑 FATAL API ERROR - STOPPING GENERATION 🛑🛑🛑")
                        print("   Error: \(message)")
                        print("   Generated \(allRoutes.count) routes before stopping.")
                        print("🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑🛑\n")
                        
                        // Save what we have and return immediately
                        await saveRoutesIncrementally(allRoutes)
                        await MainActor.run {
                            onProgressUpdate?("⛔️ API Error: \(message)")
                        }
                        
                        return GenerationResult(
                            routes: allRoutes,
                            skippedThresholds: Array(Set(skippedThresholds)),
                            coverageByThreshold: [:]
                        )
                    }
                }
                
                print("  Summary for \(threshold.minutes) min: attempted=\(attemptedCount), success=\(generatedForThreshold), outsideRange=\(outsideRange), routingFailed=\(failedRouting)")
                
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
                continent: route.continent,
                startingPoint: route.startingPoint,
                turnaroundPoint: route.turnaroundPoint,
                totalDistanceMiles: route.totalDistanceMiles,
                distanceBandMiles: route.distanceBandMiles,
                outboundPath: route.outboundPath,
                returnPath: route.returnPath,
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
    
    // MARK: - Generate Routes for Single Time Threshold
    
    /// Generates routes for a SINGLE time threshold, exhausting ALL available POIs
    /// Does not stop at 10 routes - tries every POI that could work for this threshold
    func generateRoutesForThreshold(minutes: Int, for city: City, startingPoint: StartingPoint, directionPreference: DirectionPreference = .noPreference, existingRoutes: [Route] = [], blacklistedPOINames: Set<String> = []) async -> GenerationResult {
        let generationStartTime = Date()
        let threshold = TimeThreshold(minutes: minutes)
        
        print("\n╔════════════════════════════════════════════════════════════╗")
        print("║  SINGLE THRESHOLD GENERATION - EXHAUST ALL POIs            ║")
        print("║  City: \(city.name.padding(toLength: 48, withPad: " ", startingAt: 0))  ║")
        print("║  Starting Point: \(startingPoint.name.padding(toLength: 39, withPad: " ", startingAt: 0))  ║")
        print("║  Direction: \(directionPreference.rawValue.padding(toLength: 44, withPad: " ", startingAt: 0))  ║")
        print("║  Target Threshold: \(String(minutes).padding(toLength: 37, withPad: " ", startingAt: 0)) min  ║")
        print("║  Target Distance: \(String(format: "%.2f", threshold.targetDistanceMiles).padding(toLength: 34, withPad: " ", startingAt: 0)) mi  ║")
        print("║  Valid Range: \(String(format: "%.2f-%.2f", threshold.minDistanceMiles, threshold.maxDistanceMiles).padding(toLength: 38, withPad: " ", startingAt: 0)) mi  ║")
        print("╚════════════════════════════════════════════════════════════╝\n")
        
        var allRoutes: [Route] = existingRoutes
        var usedTurnaroundPointNames: Set<String> = Set(existingRoutes.map { $0.turnaroundPoint.name })
        
        let startPoint = PointOfInterest(name: startingPoint.name, coordinate: startingPoint.coordinate, type: "landmark")
        
        await updateProgress("Generating routes for \(minutes) min threshold...")
        
        // Fetch POIs at the appropriate radius
        let radiusMeters = threshold.searchRadiusMiles * 1609.34
        
        do {
            print("  Searching for POIs at radius \(String(format: "%.2f", radiusMeters)) m (\(String(format: "%.2f", threshold.searchRadiusMiles)) mi)...")
            
            let pois = try await POIService.shared.fetchPOIs(near: startingPoint.coordinate, radiusInMeters: radiusMeters)
            print("  POI search returned \(pois.count) total POIs")
            
            // Filter out POIs we've already used
            let unusedPOIs = pois.filter { !usedTurnaroundPointNames.contains($0.name) }
            print("  After removing already-used: \(unusedPOIs.count) remaining")
            
            // Filter out manually blacklisted POIs
            let nonBlacklistedPOIs = unusedPOIs.filter { !blacklistedPOINames.contains($0.name) }
            print("  After removing manually blacklisted: \(nonBlacklistedPOIs.count) remaining")
            
            // Filter POIs by straight-line distance
            let startLoc = CLLocation(latitude: startingPoint.coordinate.latitude, longitude: startingPoint.coordinate.longitude)
            let minStraightLineMeters = (threshold.minDistanceMiles / 4.0) * 1609.34
            let maxStraightLineMeters = (threshold.maxDistanceMiles / 1.5) * 1609.34
            
            let availablePOIs = nonBlacklistedPOIs.filter { poi in
                let poiLoc = CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude)
                let straightLineDistance = poiLoc.distance(from: startLoc)
                return straightLineDistance >= 500 &&
                       straightLineDistance >= minStraightLineMeters &&
                       straightLineDistance <= maxStraightLineMeters
            }
            
            print("  After distance filtering: \(availablePOIs.count) POIs in range")
            
            // Filter by direction preference
            let directionFilteredPOIs: [PointOfInterest]
            if directionPreference != .noPreference {
                directionFilteredPOIs = availablePOIs.filter { poi in
                    let bearing = calculateBearing(from: startingPoint.coordinate, to: poi.coordinate)
                    return matchesDirection(bearing, preference: directionPreference)
                }
                print("  After direction filtering: \(directionFilteredPOIs.count) POIs")
            } else {
                directionFilteredPOIs = availablePOIs
            }
            
            var generatedCount = 0
            var attemptedCount = 0
            var failedRouting = 0
            var outsideRange = 0
            
            // Sort by priority and try ALL POIs
            let prioritizedPOIs = directionFilteredPOIs
                .sorted { $0.priority < $1.priority }
                .chunkedByPriority()
                .flatMap { $0.shuffled() }
            
            print("\n  🎯 Trying ALL \(prioritizedPOIs.count) POIs for \(minutes) min threshold...\n")
            
            for poi in prioritizedPOIs {
                attemptedCount += 1
                
                print("    [\(attemptedCount)/\(prioritizedPOIs.count)] Trying: \(poi.name)...")
                await updateProgress("[\(attemptedCount)/\(prioritizedPOIs.count)] \(poi.name)...")
                
                let result = await generateRoute(from: startPoint, to: poi, targetDistance: threshold.targetDistanceMiles, continent: city.continent)
                
                switch result {
                case .success(let route):
                    if threshold.isValidDistance(route.totalDistanceMiles) {
                        allRoutes.append(route)
                        usedTurnaroundPointNames.insert(poi.name)
                        generatedCount += 1
                        print("    [\(attemptedCount)] ✓ SUCCESS: \(poi.name) → \(String(format: "%.2f", route.totalDistanceMiles)) mi")
                        
                        await notifyRouteGenerated(route)
                        await saveRoutesIncrementally(allRoutes)
                    } else {
                        outsideRange += 1
                        print("    [\(attemptedCount)] ✗ OUTSIDE RANGE: \(poi.name) → \(String(format: "%.2f", route.totalDistanceMiles)) mi (need \(String(format: "%.2f-%.2f", threshold.minDistanceMiles, threshold.maxDistanceMiles)) mi)")
                    }
                    
                case .failedRouting:
                    failedRouting += 1
                    print("    [\(attemptedCount)] ✗ ROUTING FAILED: \(poi.name)")
                    
                case .fatalAPIError(let message):
                    print("\n🛑 FATAL API ERROR: \(message)")
                    await saveRoutesIncrementally(allRoutes)
                    return GenerationResult(routes: allRoutes, skippedThresholds: [], coverageByThreshold: [minutes: generatedCount])
                }
            }
            
            let generationDuration = Date().timeIntervalSince(generationStartTime)
            let mins = Int(generationDuration) / 60
            let secs = Int(generationDuration) % 60
            
            print("\n════════════════════════════════════════════════════════════")
            print("SINGLE THRESHOLD GENERATION COMPLETE")
            print("Threshold: \(minutes) min | Generated: \(generatedCount) routes")
            print("Attempted: \(attemptedCount) | Outside Range: \(outsideRange) | Failed: \(failedRouting)")
            print("Duration: \(mins)m \(secs)s")
            print("════════════════════════════════════════════════════════════\n")
            
            await updateProgress("Generated \(generatedCount) routes for \(minutes) min")
            
            return GenerationResult(
                routes: allRoutes,
                skippedThresholds: generatedCount == 0 ? [minutes] : [],
                coverageByThreshold: [minutes: generatedCount]
            )
            
        } catch {
            print("  ✗ Error fetching POIs: \(error)")
            return GenerationResult(routes: allRoutes, skippedThresholds: [minutes], coverageByThreshold: [:])
        }
    }
    
    // MARK: - Regenerate Single Route
    
    /// Regenerates a route to the SAME turnaround point but with a DIFFERENT path
    /// Tries to find an alternative route that doesn't overlap too much with ANY existing routes
    func regenerateRoute(oldRoute: Route, city: City, startingPoint: StartingPoint, directionPreference: DirectionPreference = .noPreference, existingRoutes: [Route] = []) async -> Route? {
        print("Regenerating route to \(oldRoute.turnaroundPoint.name) with different path...")
        
        let startPoint = PointOfInterest(name: startingPoint.name, coordinate: startingPoint.coordinate, type: "landmark")
        let turnaroundPoint = oldRoute.turnaroundPoint
        
        // Collect ALL existing paths (to avoid duplicating any route, not just routes to same point)
        let allExistingPaths = existingRoutes.flatMap { [$0.outboundPath, $0.returnPath] }
        
        print("  Checking against \(existingRoutes.count) existing routes (\(allExistingPaths.count) paths)")
        
        do {
            // Request routes from Valhalla (pedestrian profile - avoids highways)
            let valhallaOutboundAlternatives = try await ValhallaService.shared.fetchRoutes(from: startPoint.coordinate, to: turnaroundPoint.coordinate)
            let valhallaReturnAlternatives = try await ValhallaService.shared.fetchRoutes(from: turnaroundPoint.coordinate, to: startPoint.coordinate)
            
            print("  Valhalla returned \(valhallaOutboundAlternatives.count) outbound and \(valhallaReturnAlternatives.count) return alternatives")
            
            // Try each combination of outbound and return routes
            for (outIdx, valhallaOutbound) in valhallaOutboundAlternatives.enumerated() {
                for (retIdx, valhallaReturn) in valhallaReturnAlternatives.enumerated() {
                    print("  Trying combination: outbound #\(outIdx + 1), return #\(retIdx + 1)...")
                    
                    // Check if this combination is sufficiently different from ALL existing paths
                    let outboundOverlap = calculateMaxOverlapWithExisting(newPath: valhallaOutbound.coordinates, existingPaths: allExistingPaths)
                    let returnOverlap = calculateMaxOverlapWithExisting(newPath: valhallaReturn.coordinates, existingPaths: allExistingPaths)
                    
                    // Skip if too similar to existing routes (>70% overlap)
                    if outboundOverlap > 0.7 || returnOverlap > 0.7 {
                        print("    → Too similar to existing (outbound: \(String(format: "%.0f", outboundOverlap * 100))%, return: \(String(format: "%.0f", returnOverlap * 100))%) - trying next")
                        continue
                    }
                    
                    // Check for highway-like characteristics
                    if let reason = detectHighwayCharacteristics(coordinates: valhallaOutbound.coordinates, distanceMeters: valhallaOutbound.distanceMeters) {
                        print("    → Outbound looks like highway: \(reason) - trying next")
                        continue
                    }
                    
                    if let reason = detectHighwayCharacteristics(coordinates: valhallaReturn.coordinates, distanceMeters: valhallaReturn.distanceMeters) {
                        print("    → Return looks like highway: \(reason) - trying next")
                        continue
                    }
                    
                    print("    → ✓ Found valid alternative route!")
                    
                    // Build the new route
                    let totalDistanceMeters = valhallaOutbound.distanceMeters + valhallaReturn.distanceMeters
                    let totalDistanceMiles = totalDistanceMeters / 1609.34
                    let validTimes = calculateValidSessionTimes(distanceMiles: totalDistanceMiles)
                    let distanceBand = inferDistanceBand(from: totalDistanceMiles)
                    
                    let newRoute = Route(
                        name: turnaroundPoint.name,
                        continent: city.continent,
                        startingPoint: startPoint,
                        turnaroundPoint: turnaroundPoint,
                        totalDistanceMiles: totalDistanceMiles,
                        distanceBandMiles: distanceBand,
                        outboundPath: valhallaOutbound.coordinates,
                        returnPath: valhallaReturn.coordinates,
                        validSessionTimes: validTimes
                    )
                    
                    return newRoute
                }
            }
            
            print("  ⚠️ No sufficiently different alternative found")
            return nil
            
        } catch {
            print("  Regenerate failed: \(error)")
            return nil
        }
    }
    
    /// Calculate the maximum overlap between a new path and any of the existing paths
    private func calculateMaxOverlapWithExisting(newPath: [CLLocationCoordinate2D], existingPaths: [[CLLocationCoordinate2D]]) -> Double {
        guard !existingPaths.isEmpty else { return 0 }
        
        var maxOverlap: Double = 0
        for existingPath in existingPaths {
            let overlap = OverlapCalculator.shared.calculateOverlap(pathA: newPath, pathB: existingPath)
            maxOverlap = max(maxOverlap, overlap)
        }
        return maxOverlap
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
    
    private func generateRoute(from start: PointOfInterest, to turnaroundPoint: PointOfInterest, targetDistance: Double, continent: String) async -> RouteGenerationResult {
        // Valhalla approach (pedestrian profile - automatically avoids highways):
        // 1. Valhalla generates multiple route alternatives
        // 2. Try combinations to find the best loop (lowest overlap)
        // 3. Check for highway-like characteristics (extra safety)
        
        do {
            print("        → Fetching routes from Valhalla...")
            
            // Fetch multiple route alternatives from Valhalla
            async let valhallaOutboundTask = ValhallaService.shared.fetchRoutes(from: start.coordinate, to: turnaroundPoint.coordinate)
            async let valhallaReturnTask = ValhallaService.shared.fetchRoutes(from: turnaroundPoint.coordinate, to: start.coordinate)
            
            let (valhallaOutboundOpts, valhallaReturnOpts) = try await (valhallaOutboundTask, valhallaReturnTask)
            
            guard !valhallaOutboundOpts.isEmpty else {
                print("        → No outbound routes from Valhalla")
                return .failedRouting
            }
            
            guard !valhallaReturnOpts.isEmpty else {
                print("        → No return routes from Valhalla")
                return .failedRouting
            }
            
            print("        → Valhalla: \(valhallaOutboundOpts.count) outbound options, \(valhallaReturnOpts.count) return options")
            
            // Try all combinations to find the best loop (lowest overlap)
            var bestRoute: Route?
            var bestOverlap: Double = 1.0
            
            for (outIdx, outbound) in valhallaOutboundOpts.enumerated() {
                // Check outbound for highway characteristics
                if let reason = detectHighwayCharacteristics(coordinates: outbound.coordinates, distanceMeters: outbound.distanceMeters) {
                    print("        → Outbound #\(outIdx + 1) looks like highway: \(reason) - skipping")
                    continue
                }
                
                for (retIdx, returnPath) in valhallaReturnOpts.enumerated() {
                    // Check return for highway characteristics
                    if let reason = detectHighwayCharacteristics(coordinates: returnPath.coordinates, distanceMeters: returnPath.distanceMeters) {
                        if outIdx == 0 { // Only print once per return option
                            print("        → Return #\(retIdx + 1) looks like highway: \(reason) - skipping")
                        }
                        continue
                    }
                    
                    // Calculate overlap between this combination
                    let overlap = OverlapCalculator.shared.calculateOverlap(pathA: outbound.coordinates, pathB: returnPath.coordinates)
                    
                    let totalDistanceMeters = outbound.distanceMeters + returnPath.distanceMeters
                    let totalDistanceMiles = totalDistanceMeters / 1609.34
                    
                    print("        → Combo [\(outIdx + 1),\(retIdx + 1)]: \(String(format: "%.2f", totalDistanceMiles)) mi, overlap=\(String(format: "%.0f", overlap * 100))%")
                    
                    // Keep this combination if it has lower overlap
                    if overlap < bestOverlap {
                        bestOverlap = overlap
                        
                        let validTimes = calculateValidSessionTimes(distanceMiles: totalDistanceMiles)
                        let distanceBand = inferDistanceBand(from: totalDistanceMiles)
                        
                        bestRoute = Route(
                            name: turnaroundPoint.name,
                            continent: continent,
                            startingPoint: start,
                            turnaroundPoint: turnaroundPoint,
                            totalDistanceMiles: totalDistanceMiles,
                            distanceBandMiles: distanceBand,
                            outboundPath: outbound.coordinates,
                            returnPath: returnPath.coordinates,
                            validSessionTimes: validTimes
                        )
                    }
                }
            }
            
            guard let route = bestRoute else {
                print("        → No valid route combinations found")
                return .failedRouting
            }
            
            print("        → ✓ Best loop: \(String(format: "%.2f", route.totalDistanceMiles)) mi, overlap=\(String(format: "%.0f", bestOverlap * 100))%")
            
            return .success(route)
            
        } catch {
            print("        → Valhalla error for \(turnaroundPoint.name): \(error)")
            return .failedRouting
        }
    }
    
    // MARK: - Highway Detection
    
    /// Detects if a path has highway-like characteristics
    /// Returns nil if path looks normal, or a reason string if it looks like a highway
    /// NOTE: Thresholds are intentionally lenient - city grids have long straight streets
    private func detectHighwayCharacteristics(coordinates: [CLLocationCoordinate2D], distanceMeters: Double) -> String? {
        guard coordinates.count >= 2 else { return nil }
        
        // Check 1: Straightness ratio (VERY lenient - only catch extreme cases)
        // City grids can be quite straight, so only flag if nearly perfect straight line
        let straightLineDistance = calculateStraightLineDistance(from: coordinates.first!, to: coordinates.last!)
        let straightnessRatio = straightLineDistance / distanceMeters
        
        // Only flag if >98% straight AND over 2km - this catches true highways
        if straightnessRatio > 0.98 && distanceMeters > 2000 {
            return "extremely straight (ratio: \(String(format: "%.2f", straightnessRatio)))"
        }
        
        // Check 2: Long straight segments (VERY lenient)
        // Only flag segments over 5km that are 99%+ straight - definite highway behavior
        if let longSegment = findLongestStraightSegment(coordinates: coordinates) {
            if longSegment.distance > 5000 && longSegment.straightness > 0.99 {
                return "highway-like segment (\(Int(longSegment.distance))m at \(String(format: "%.0f", longSegment.straightness * 100))% straight)"
            }
        }
        
        // Check 3: Low coordinate density (disabled - not reliable)
        // City streets can have low density too, this causes too many false positives
        // let pointsPerKm = Double(coordinates.count) / (distanceMeters / 1000.0)
        
        // Check 4: Average segment length (disabled - not reliable)
        // Grid cities naturally have longer segments
        // let avgSegmentLength = distanceMeters / Double(max(coordinates.count - 1, 1))
        
        return nil
    }
    
    /// Calculate straight-line distance between two coordinates in meters
    private func calculateStraightLineDistance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
        return startLoc.distance(from: endLoc)
    }
    
    /// Find the longest straight segment in a path
    private func findLongestStraightSegment(coordinates: [CLLocationCoordinate2D]) -> (distance: Double, straightness: Double)? {
        guard coordinates.count >= 3 else { return nil }
        
        var longestDistance: Double = 0
        var longestStraightness: Double = 0
        
        // Check segments of varying lengths (10-50 points)
        for windowSize in stride(from: 10, through: min(50, coordinates.count), by: 5) {
            for i in 0...(coordinates.count - windowSize) {
                let segment = Array(coordinates[i..<(i + windowSize)])
                let pathDistance = calculatePathDistance(segment)
                let straightDistance = calculateStraightLineDistance(from: segment.first!, to: segment.last!)
                let straightness = straightDistance / max(pathDistance, 1)
                
                if pathDistance > longestDistance && straightness > 0.9 {
                    longestDistance = pathDistance
                    longestStraightness = straightness
                }
            }
        }
        
        return longestDistance > 0 ? (longestDistance, longestStraightness) : nil
    }
    
    /// Calculate total path distance along coordinates
    private func calculatePathDistance(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        
        var totalDistance: Double = 0
        for i in 1..<coordinates.count {
            totalDistance += calculateStraightLineDistance(from: coordinates[i-1], to: coordinates[i])
        }
        return totalDistance
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
    
    private func inferDistanceBand(from distance: Double) -> Double {
        let bands: [Double] = [1.0, 2.0, 4.0, 7.5, 9.5, 13.0, 16.0]
        return bands.min(by: { abs($0 - distance) < abs($1 - distance) }) ?? 4.0
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
