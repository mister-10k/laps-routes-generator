import Foundation

class PersistenceService {
    static let shared = PersistenceService()
    
    private let fileManager = FileManager.default
    private let routesDirectory: URL
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("LapsRouteGenerator", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appFolder.path) {
            do {
                try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
                print("📁 Created routes directory: \(appFolder.path)")
            } catch {
                print("❌ Failed to create routes directory: \(error.localizedDescription)")
            }
        } else {
            print("📁 Routes directory exists: \(appFolder.path)")
        }
        
        self.routesDirectory = appFolder
    }
    
    private func fileURL(for cityName: String) -> URL {
        let safeFileName = cityName
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        return routesDirectory.appendingPathComponent("\(safeFileName)_routes.json")
    }
    
    private func blacklistURL(for cityName: String) -> URL {
        let safeFileName = cityName
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        return routesDirectory.appendingPathComponent("\(safeFileName)_blacklist.json")
    }
    
    private func thresholdBlacklistURL(for cityName: String) -> URL {
        let safeFileName = cityName
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        return routesDirectory.appendingPathComponent("\(safeFileName)_threshold_blacklist.json")
    }
    
    // MARK: - Save Routes
    
    func saveRoutes(_ routes: [Route], for cityName: String) {
        let url = fileURL(for: cityName)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(routes)
            try data.write(to: url, options: .atomic)
            print("✅ Saved \(routes.count) routes for \(cityName)")
            print("   Location: \(url.path)")
        } catch let encodingError as EncodingError {
            print("❌ Failed to encode routes for \(cityName): \(encodingError)")
        } catch {
            print("❌ Failed to save routes for \(cityName): \(error.localizedDescription)")
            print("   Attempted location: \(url.path)")
        }
    }
    
    // MARK: - Load Routes
    
    func loadRoutes(for cityName: String) -> [Route]? {
        let url = fileURL(for: cityName)
        
        guard fileManager.fileExists(atPath: url.path) else {
            print("📂 No saved routes found for \(cityName) at \(url.path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let routes = try JSONDecoder().decode([Route].self, from: data)
            print("✅ Loaded \(routes.count) routes for \(cityName)")
            return routes
        } catch let decodingError as DecodingError {
            print("❌ Failed to decode routes for \(cityName): \(decodingError)")
            // If decoding fails, the file might be corrupted - delete it
            print("   Removing corrupted file...")
            try? fileManager.removeItem(at: url)
            return nil
        } catch {
            print("❌ Failed to load routes for \(cityName): \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Check if City Has Saved Routes
    
    func hasSavedRoutes(for cityName: String) -> Bool {
        let url = fileURL(for: cityName)
        return fileManager.fileExists(atPath: url.path)
    }
    
    // MARK: - Delete Routes
    
    func deleteRoutes(for cityName: String) {
        let url = fileURL(for: cityName)
        try? fileManager.removeItem(at: url)
        print("Deleted routes for \(cityName)")
    }
    
    // MARK: - List Cities with Saved Routes
    
    func citiesWithSavedRoutes() -> [String] {
        guard let files = try? fileManager.contentsOfDirectory(at: routesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.contains("_routes") }
            .map { $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_routes", with: "") }
    }
    
    // MARK: - Blacklist Management
    
    /// Blacklisted POI info - stores the POI name for display and identification
    struct BlacklistedPOI: Codable, Hashable {
        let name: String
        let latitude: Double
        let longitude: Double
    }
    
    /// Add a POI to the blacklist for a city
    /// Returns true if added, false if already blacklisted
    @discardableResult
    func addToBlacklist(poi: PointOfInterest, for cityName: String) -> Bool {
        let blacklist = loadBlacklist(for: cityName)
        
        // Check if already blacklisted by name
        if blacklist.contains(where: { $0.name == poi.name }) {
            print("⚠️ Already blacklisted: \(poi.name) for \(cityName)")
            return false
        }
        
        var updatedBlacklist = blacklist
        let entry = BlacklistedPOI(name: poi.name, latitude: poi.latitude, longitude: poi.longitude)
        updatedBlacklist.insert(entry)
        saveBlacklist(updatedBlacklist, for: cityName)
        print("🚫 Blacklisted: \(poi.name) for \(cityName)")
        return true
    }
    
    /// Remove a POI from the blacklist
    func removeFromBlacklist(poiName: String, for cityName: String) {
        var blacklist = loadBlacklist(for: cityName)
        blacklist = blacklist.filter { $0.name != poiName }
        saveBlacklist(blacklist, for: cityName)
        print("✅ Removed from blacklist: \(poiName) for \(cityName)")
    }
    
    /// Check if a POI is blacklisted
    func isBlacklisted(poiName: String, for cityName: String) -> Bool {
        let blacklist = loadBlacklist(for: cityName)
        return blacklist.contains(where: { $0.name == poiName })
    }
    
    /// Get all blacklisted POI names for a city
    func getBlacklistedNames(for cityName: String) -> Set<String> {
        let blacklist = loadBlacklist(for: cityName)
        return Set(blacklist.map { $0.name })
    }
    
    /// Load the blacklist for a city
    func loadBlacklist(for cityName: String) -> Set<BlacklistedPOI> {
        let url = blacklistURL(for: cityName)
        
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let blacklist = try JSONDecoder().decode(Set<BlacklistedPOI>.self, from: data)
            return blacklist
        } catch {
            print("❌ Failed to load blacklist for \(cityName): \(error.localizedDescription)")
            return []
        }
    }
    
    /// Save the blacklist for a city
    private func saveBlacklist(_ blacklist: Set<BlacklistedPOI>, for cityName: String) {
        let url = blacklistURL(for: cityName)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(blacklist)
            try data.write(to: url, options: .atomic)
            print("💾 Saved blacklist (\(blacklist.count) items) for \(cityName)")
        } catch {
            print("❌ Failed to save blacklist for \(cityName): \(error.localizedDescription)")
        }
    }
    
    /// Clear the blacklist for a city
    func clearBlacklist(for cityName: String) {
        let url = blacklistURL(for: cityName)
        try? fileManager.removeItem(at: url)
        print("🗑️ Cleared blacklist for \(cityName)")
    }
    
    /// Get blacklist count for a city
    func blacklistCount(for cityName: String) -> Int {
        return loadBlacklist(for: cityName).count
    }
    
    // MARK: - Per-Threshold Blacklist Management
    // This blacklist is auto-populated when POIs fail due to outside range
    // for a specific duration threshold. Unlike the manual blacklist, this is per-threshold.
    
    /// Per-threshold blacklist structure: [threshold_minutes: Set<poi_name>]
    typealias ThresholdBlacklist = [Int: Set<String>]
    
    /// Add a POI to the per-threshold blacklist
    func addToThresholdBlacklist(poiName: String, threshold: Int, for cityName: String) {
        var blacklist = loadThresholdBlacklist(for: cityName)
        
        if blacklist[threshold] == nil {
            blacklist[threshold] = []
        }
        
        // Only log if it's a new addition
        if !blacklist[threshold]!.contains(poiName) {
            blacklist[threshold]!.insert(poiName)
            saveThresholdBlacklist(blacklist, for: cityName)
            print("🚫 Threshold blacklisted: \(poiName) for \(threshold) min in \(cityName)")
        }
    }
    
    /// Get blacklisted POI names for a specific threshold
    func getThresholdBlacklistedNames(threshold: Int, for cityName: String) -> Set<String> {
        let blacklist = loadThresholdBlacklist(for: cityName)
        return blacklist[threshold] ?? []
    }
    
    /// Get total count of all per-threshold blacklisted entries
    func thresholdBlacklistCount(for cityName: String) -> Int {
        let blacklist = loadThresholdBlacklist(for: cityName)
        return blacklist.values.reduce(0) { $0 + $1.count }
    }
    
    /// Load the per-threshold blacklist for a city
    func loadThresholdBlacklist(for cityName: String) -> ThresholdBlacklist {
        let url = thresholdBlacklistURL(for: cityName)
        
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: url)
            let blacklist = try JSONDecoder().decode(ThresholdBlacklist.self, from: data)
            return blacklist
        } catch {
            print("❌ Failed to load threshold blacklist for \(cityName): \(error.localizedDescription)")
            return [:]
        }
    }
    
    /// Save the per-threshold blacklist for a city
    private func saveThresholdBlacklist(_ blacklist: ThresholdBlacklist, for cityName: String) {
        let url = thresholdBlacklistURL(for: cityName)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(blacklist)
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ Failed to save threshold blacklist for \(cityName): \(error.localizedDescription)")
        }
    }
    
    /// Clear the per-threshold blacklist for a city
    func clearThresholdBlacklist(for cityName: String) {
        let url = thresholdBlacklistURL(for: cityName)
        try? fileManager.removeItem(at: url)
        print("🗑️ Cleared threshold blacklist for \(cityName)")
    }
    
    /// Clear ALL blacklists (manual + per-threshold) for a city
    func clearAllBlacklists(for cityName: String) {
        clearBlacklist(for: cityName)
        clearThresholdBlacklist(for: cityName)
        print("🗑️ Cleared all blacklists for \(cityName)")
    }
    
    /// Get combined blacklist count (manual + per-threshold unique entries)
    func totalBlacklistCount(for cityName: String) -> Int {
        let manualCount = blacklistCount(for: cityName)
        let thresholdCount = thresholdBlacklistCount(for: cityName)
        return manualCount + thresholdCount
    }
    
    // MARK: - New Route IDs (persisted "NEW" tags)
    
    private func newRouteIdsURL(for cityName: String) -> URL {
        let safeFileName = cityName
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        return routesDirectory.appendingPathComponent("\(safeFileName)_new_route_ids.json")
    }
    
    /// Save the set of "new" route IDs for a city
    func saveNewRouteIds(_ ids: Set<UUID>, for cityName: String) {
        let url = newRouteIdsURL(for: cityName)
        do {
            let idStrings = ids.map { $0.uuidString }
            let data = try JSONEncoder().encode(idStrings)
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ Failed to save new route IDs: \(error.localizedDescription)")
        }
    }
    
    /// Load the set of "new" route IDs for a city
    func loadNewRouteIds(for cityName: String) -> Set<UUID> {
        let url = newRouteIdsURL(for: cityName)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let idStrings = try JSONDecoder().decode([String].self, from: data)
            return Set(idStrings.compactMap { UUID(uuidString: $0) })
        } catch {
            print("❌ Failed to load new route IDs: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Mark a route as "seen" (remove from new IDs)
    func markRouteSeen(id: UUID, for cityName: String) {
        var ids = loadNewRouteIds(for: cityName)
        ids.remove(id)
        saveNewRouteIds(ids, for: cityName)
    }
    
    /// Add a route ID to the "new" set
    func addNewRouteId(_ id: UUID, for cityName: String) {
        var ids = loadNewRouteIds(for: cityName)
        ids.insert(id)
        saveNewRouteIds(ids, for: cityName)
    }
    
    /// Clear all "new" route IDs for a city
    func clearNewRouteIds(for cityName: String) {
        let url = newRouteIdsURL(for: cityName)
        try? fileManager.removeItem(at: url)
    }
}

