import Foundation
import CoreLocation

class OverlapCalculator {
    static let shared = OverlapCalculator()
    
    // Threshold in meters to consider points "overlapping"
    private let overlapThreshold: Double = 20.0
    
    func calculateOverlap(pathA: [CLLocationCoordinate2D], pathB: [CLLocationCoordinate2D]) -> Double {
        guard !pathA.isEmpty, !pathB.isEmpty else { return 0.0 }
        
        // Check how many points in A are close to any point in B
        let overlappingPointsA = countOverlappingPoints(source: pathA, target: pathB)
        let overlappingPointsB = countOverlappingPoints(source: pathB, target: pathA)
        
        let percentA = Double(overlappingPointsA) / Double(pathA.count)
        let percentB = Double(overlappingPointsB) / Double(pathB.count)
        
        // Return average overlap
        return (percentA + percentB) / 2.0
    }
    
    private func countOverlappingPoints(source: [CLLocationCoordinate2D], target: [CLLocationCoordinate2D]) -> Int {
        var count = 0
        for point in source {
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            // Check if this point is close to ANY point in target
            // Optimization: Could use spatial index, but linear scan is fine for small paths
            for targetPoint in target {
                let targetLocation = CLLocation(latitude: targetPoint.latitude, longitude: targetPoint.longitude)
                if location.distance(from: targetLocation) < overlapThreshold {
                    count += 1
                    break
                }
            }
        }
        return count
    }
}

