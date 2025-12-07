import Foundation
import CoreLocation
import MapKit

// MARK: - Supporting Types

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
    
    func generateRoutes(for city: City, existingRoutes: [Route] = [], blacklistedPOINames: Set<String> = []) async -> GenerationResult {
        let generationStartTime = Date()
        
        print("\n╔════════════════════════════════════════════════════════════╗")
        print("║  ROUTE GENERATION STARTING                                  ║")
        print("║  City: \(city.name.padding(toLength: 48, withPad: " ", startingAt: 0))  ║")
        print("║  Target: \(routesPerThreshold) unique routes per time threshold               ║")
        print("║  Thresholds: 5, 10, 15 ... 120 min (\(allThresholds.count) total)             ║")
        print("║  Existing routes to keep: \(String(existingRoutes.count).padding(toLength: 29, withPad: " ", startingAt: 0))  ║")
        print("║  Blacklisted POIs: \(String(blacklistedPOINames.count).padding(toLength: 36, withPad: " ", startingAt: 0))  ║")
        print("╚════════════════════════════════════════════════════════════╝\n")
        
        // Start with existing routes
        var allRoutes: [Route] = existingRoutes
        var usedMidpointIds: Set<UUID> = Set(existingRoutes.map { $0.midpoint.id }) // Track POIs already used
        var skippedThresholds: [Int] = []
        
        let startPoint = PointOfInterest(name: city.landmarkName, coordinate: city.coordinate, type: "landmark")
        print("Starting point: \(startPoint.name) at (\(String(format: "%.4f", city.coordinate.latitude)), \(String(format: "%.4f", city.coordinate.longitude)))")
        print("Starting with \(existingRoutes.count) existing routes, \(usedMidpointIds.count) POIs already used, \(blacklistedPOINames.count) blacklisted\n")
        
        // Process thresholds in order
        for threshold in allThresholds {
            print("\n────────────────────────────────────────────────────────────")
            print("THRESHOLD: \(threshold.minutes) min | Total routes so far: \(allRoutes.count) | Used POIs: \(usedMidpointIds.count)")
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
                
                let pois = try await POIService.shared.fetchPOIs(near: city.coordinate, radiusInMeters: radiusMeters)
                print("  POI search returned \(pois.count) total POIs")
                
                // Filter out POIs we've already used
                let unusedPOIs = pois.filter { !usedMidpointIds.contains($0.id) }
                let alreadyUsedCount = pois.count - unusedPOIs.count
                print("  After removing already-used: \(unusedPOIs.count) remaining (\(alreadyUsedCount) already used)")
                
                // Filter out blacklisted POIs
                let nonBlacklistedPOIs = unusedPOIs.filter { !blacklistedPOINames.contains($0.name) }
                let blacklistedCount = unusedPOIs.count - nonBlacklistedPOIs.count
                if blacklistedCount > 0 {
                    print("  After removing blacklisted: \(nonBlacklistedPOIs.count) remaining (\(blacklistedCount) blacklisted)")
                }
                
                // Filter POIs by straight-line distance to estimate if they'll produce valid routes
                // Roads are typically 1.3-1.6x longer than straight-line, so:
                // - For a target round-trip of X miles, each leg is X/2 miles
                // - Straight-line distance should be roughly (X/2) / 1.4 = X/2.8
                // - Allow some tolerance: min = targetDistance/4, max = targetDistance/1.5
                let startLoc = CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
                let minStraightLineMeters = (threshold.minDistanceMiles / 4.0) * 1609.34  // Very conservative min
                let maxStraightLineMeters = (threshold.maxDistanceMiles / 1.5) * 1609.34  // Account for winding roads
                
                let availablePOIs = nonBlacklistedPOIs.filter { poi in
                    let poiLoc = CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude)
                    let straightLineDistance = poiLoc.distance(from: startLoc)
                    // Must be at least 500m away AND within our estimated useful range
                    return straightLineDistance >= 500 && 
                           straightLineDistance >= minStraightLineMeters && 
                           straightLineDistance <= maxStraightLineMeters
                }
                
                let filteredOutCount = nonBlacklistedPOIs.count - availablePOIs.count
                print("  After distance filtering: \(availablePOIs.count) POIs in straight-line range \(String(format: "%.2f", minStraightLineMeters/1609.34))-\(String(format: "%.2f", maxStraightLineMeters/1609.34)) mi (\(filteredOutCount) filtered out)")
                
                print("  Target route distance: \(String(format: "%.2f", threshold.targetDistanceMiles)) mi | Valid range: \(String(format: "%.2f", threshold.minDistanceMiles))-\(String(format: "%.2f", threshold.maxDistanceMiles)) mi")
                
                var generatedForThreshold = 0
                var attemptedCount = 0
                var failedOSRM = 0
                var outsideRange = 0
                var consecutiveOutsideRange = 0
                let maxConsecutiveOutsideRange = 20
                
                // Sort by priority (famous/popular places first) with shuffle within each tier for variety
                let prioritizedPOIs = availablePOIs
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
                    
                    if let route = await generateRoute(from: startPoint, to: poi, targetDistance: threshold.targetDistanceMiles) {
                        // Verify the route actually works for this threshold
                        if threshold.isValidDistance(route.totalDistanceMiles) {
                            allRoutes.append(route)
                            usedMidpointIds.insert(poi.id)
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
                            print("    [\(attemptedCount)] ✗ OUTSIDE RANGE [\(currentCount)/\(routesPerThreshold)] (\(consecutiveOutsideRange)/\(maxConsecutiveOutsideRange)): \(poi.name) → \(String(format: "%.2f", route.totalDistanceMiles)) mi (need \(String(format: "%.2f", threshold.minDistanceMiles))-\(String(format: "%.2f", threshold.maxDistanceMiles)) mi)")
                        }
                    } else {
                        failedOSRM += 1
                        // Don't count OSRM failures toward consecutive outside-range
                        print("    [\(attemptedCount)] ✗ OSRM FAILED [\(currentCount)/\(routesPerThreshold)]: \(poi.name)")
                    }
                }
                
                print("  Summary for \(threshold.minutes) min: attempted=\(attemptedCount), success=\(generatedForThreshold), outsideRange=\(outsideRange), osrmFailed=\(failedOSRM)")
                
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
                midpoint: route.midpoint,
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
    
    func regenerateRoute(oldRoute: Route, city: City) async -> Route? {
        // Find which time thresholds this route serves
        guard let primaryThreshold = allThresholds.first(where: { $0.isValidDistance(oldRoute.totalDistanceMiles) }) else {
            print("Could not find matching threshold for route distance \(oldRoute.totalDistanceMiles)")
            return nil
        }
        
        print("Regenerating route for \(primaryThreshold.minutes) min threshold")
        
        let radiusMeters = primaryThreshold.searchRadiusMiles * 1609.34
        
        do {
            let pois = try await POIService.shared.fetchPOIs(near: city.coordinate, radiusInMeters: radiusMeters)
            
            // Filter out the current POI and those too close to start
            let startLoc = CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
            let candidates = pois.filter { poi in
                if poi.id == oldRoute.midpoint.id { return false }
                let poiLoc = CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude)
                return poiLoc.distance(from: startLoc) >= 500
            }.shuffled()
            
            let startPoint = oldRoute.startingPoint
            
            // Try up to 10 candidates
            for poi in candidates.prefix(10) {
                if let newRoute = await generateRoute(from: startPoint, to: poi, targetDistance: primaryThreshold.targetDistanceMiles) {
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
    
    private func generateRoute(from start: PointOfInterest, to midpoint: PointOfInterest, targetDistance: Double) async -> Route? {
        do {
            print("        → Calling OSRM for outbound & return paths...")
            
            async let outboundTask = OSRMService.shared.fetchRoutes(from: start.coordinate, to: midpoint.coordinate)
            async let returnTask = OSRMService.shared.fetchRoutes(from: midpoint.coordinate, to: start.coordinate)
            
            let (outboundOpts, returnOpts) = try await (outboundTask, returnTask)
            
            print("        → OSRM returned \(outboundOpts.count) outbound options, \(returnOpts.count) return options")
            
            if outboundOpts.isEmpty || returnOpts.isEmpty {
                print("        → No route options from OSRM")
                return nil
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
                return nil
            }
            
            let totalDistanceMeters = bestOut.distanceMeters + bestRet.distanceMeters
            let totalDistanceMiles = totalDistanceMeters / 1609.34
            
            print("        → Best pair: outbound=\(String(format: "%.2f", bestOut.distanceMeters/1609.34)) mi, return=\(String(format: "%.2f", bestRet.distanceMeters/1609.34)) mi, total=\(String(format: "%.2f", totalDistanceMiles)) mi, overlap=\(String(format: "%.0f", minOverlap * 100))%")
            
            // Generate metadata
            let validTimes = calculateValidSessionTimes(distanceMiles: totalDistanceMiles)
            let pacing = generatePacing(distanceMiles: totalDistanceMiles)
            
            // Infer distance band for backwards compatibility
            let distanceBand = inferDistanceBand(from: totalDistanceMiles)
            
            return Route(
                name: midpoint.name,
                startingPoint: start,
                midpoint: midpoint,
                totalDistanceMiles: totalDistanceMiles,
                distanceBandMiles: distanceBand,
                outboundPath: bestOut.coordinates,
                returnPath: bestRet.coordinates,
                pacingInstructions: pacing,
                validSessionTimes: validTimes
            )
            
        } catch {
            print("        → OSRM error for \(midpoint.name): \(error)")
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
