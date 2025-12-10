import Foundation

/// Helper for persisting UI selections across app launches
struct SelectionPersistence {
    private static let cityKey = "selectedCityName"
    private static let startingPointKey = "selectedStartingPointName"
    private static let directionKey = "selectedDirection"
    
    // MARK: - Save Methods
    
    static func saveCity(_ cityName: String) {
        UserDefaults.standard.set(cityName, forKey: cityKey)
    }
    
    static func saveStartingPoint(_ startingPointName: String) {
        UserDefaults.standard.set(startingPointName, forKey: startingPointKey)
    }
    
    static func saveDirection(_ direction: DirectionPreference) {
        UserDefaults.standard.set(direction.rawValue, forKey: directionKey)
    }
    
    // MARK: - Load Methods
    
    static func loadCity(from cities: [City]) -> City? {
        guard let cityName = UserDefaults.standard.string(forKey: cityKey) else {
            return nil
        }
        return cities.first { $0.name == cityName }
    }
    
    static func loadStartingPoint(for city: City) -> StartingPoint? {
        guard let startingPointName = UserDefaults.standard.string(forKey: startingPointKey) else {
            return nil
        }
        return city.startingPoints.first { $0.name == startingPointName }
    }
    
    static func loadDirection() -> DirectionPreference? {
        guard let directionString = UserDefaults.standard.string(forKey: directionKey),
              let direction = DirectionPreference(rawValue: directionString) else {
            return nil
        }
        return direction
    }
}

