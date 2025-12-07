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
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_routes", with: "") }
    }
}

