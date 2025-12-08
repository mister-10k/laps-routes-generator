import Foundation
import CoreLocation

struct Cities {
    static let all: [City] = [
        // NORTH AMERICA
        City(name: "New York City", continent: "North America", startingPoints: [
            StartingPoint(name: "Empire State Building", coordinate: CLLocationCoordinate2D(latitude: 40.748817, longitude: -73.985428)),
            StartingPoint(name: "Barclays Center", coordinate: CLLocationCoordinate2D(latitude: 40.683, longitude: -73.976))
        ]),
        City(name: "Los Angeles", continent: "North America", startingPoints: [
            StartingPoint(name: "Crypto.com Arena", coordinate: CLLocationCoordinate2D(latitude: 34.043024, longitude: -118.267153))
        ]),
        City(name: "Mexico City", continent: "North America", startingPoints: [
            StartingPoint(name: "Estadio Azteca", coordinate: CLLocationCoordinate2D(latitude: 19.3029, longitude: -99.1506))
        ]),
        
        // SOUTH AMERICA
        City(name: "Bogotá", continent: "South America", startingPoints: [
            StartingPoint(name: "Estadio El Campín", coordinate: CLLocationCoordinate2D(latitude: 4.6469, longitude: -74.0809))
        ]),
        City(name: "Buenos Aires", continent: "South America", startingPoints: [
            StartingPoint(name: "La Bombonera", coordinate: CLLocationCoordinate2D(latitude: -34.6354, longitude: -58.3648))
        ]),
        City(name: "Rio de Janeiro", continent: "South America", startingPoints: [
            StartingPoint(name: "Maracanã Stadium", coordinate: CLLocationCoordinate2D(latitude: -22.91217, longitude: -43.23017))
        ]),
        
        // EUROPE
        City(name: "London", continent: "Europe", startingPoints: [
            StartingPoint(name: "Wembley Stadium", coordinate: CLLocationCoordinate2D(latitude: 51.5560, longitude: -0.2795))
        ]),
        City(name: "Paris", continent: "Europe", startingPoints: [
            StartingPoint(name: "Eiffel Tower", coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945))
        ]),
        City(name: "Rome", continent: "Europe", startingPoints: [
            StartingPoint(name: "The Colosseum", coordinate: CLLocationCoordinate2D(latitude: 41.8902, longitude: 12.4922))
        ]),
        
        // AFRICA
        City(name: "Cairo", continent: "Africa", startingPoints: [
            StartingPoint(name: "Cairo International Stadium", coordinate: CLLocationCoordinate2D(latitude: 30.068419, longitude: 31.312285))
        ]),
        City(name: "Accra", continent: "Africa", startingPoints: [
            StartingPoint(name: "Accra Sports Stadium", coordinate: CLLocationCoordinate2D(latitude: 5.551051, longitude: -0.191801))
        ]),
        City(name: "Johannesburg", continent: "Africa", startingPoints: [
            StartingPoint(name: "FNB Stadium", coordinate: CLLocationCoordinate2D(latitude: -26.2349, longitude: 27.9821))
        ]),
        
        // ASIA
        City(name: "Tokyo", continent: "Asia", startingPoints: [
            StartingPoint(name: "Tokyo National Stadium", coordinate: CLLocationCoordinate2D(latitude: 35.6785, longitude: 139.7145))
        ]),
        City(name: "Dubai", continent: "Asia", startingPoints: [
            StartingPoint(name: "Burj Khalifa", coordinate: CLLocationCoordinate2D(latitude: 25.1972, longitude: 55.2744))
        ]),
        City(name: "Singapore", continent: "Asia", startingPoints: [
            StartingPoint(name: "Singapore National Stadium", coordinate: CLLocationCoordinate2D(latitude: 1.3039, longitude: 103.8744))
        ]),
        
        // AUSTRALIA
        City(name: "Sydney", continent: "Australia", startingPoints: [
            StartingPoint(name: "Sydney Cricket Ground", coordinate: CLLocationCoordinate2D(latitude: -33.8917, longitude: 151.2247))
        ]),
        City(name: "Melbourne", continent: "Australia", startingPoints: [
            StartingPoint(name: "Melbourne Cricket Ground", coordinate: CLLocationCoordinate2D(latitude: -37.8200, longitude: 144.9835))
        ]),
        City(name: "Brisbane", continent: "Australia", startingPoints: [
            StartingPoint(name: "The Gabba", coordinate: CLLocationCoordinate2D(latitude: -27.4858, longitude: 153.0381))
        ])
    ]
}

