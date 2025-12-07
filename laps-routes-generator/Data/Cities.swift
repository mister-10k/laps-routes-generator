import Foundation
import CoreLocation

struct Cities {
    static let all: [City] = [
        // NORTH AMERICA
        City(name: "New York City", coordinate: CLLocationCoordinate2D(latitude: 40.748817, longitude: -73.985428), landmarkName: "Empire State Building"),
        City(name: "Los Angeles", coordinate: CLLocationCoordinate2D(latitude: 34.043024, longitude: -118.267153), landmarkName: "Crypto.com Arena"),
        City(name: "Mexico City", coordinate: CLLocationCoordinate2D(latitude: 19.3029, longitude: -99.1506), landmarkName: "Estadio Azteca"),
        
        // SOUTH AMERICA
        City(name: "Bogotá", coordinate: CLLocationCoordinate2D(latitude: 4.6469, longitude: -74.0809), landmarkName: "Estadio El Campín"),
        City(name: "Buenos Aires", coordinate: CLLocationCoordinate2D(latitude: -34.6354, longitude: -58.3648), landmarkName: "La Bombonera"),
        City(name: "Rio de Janeiro", coordinate: CLLocationCoordinate2D(latitude: -22.91217, longitude: -43.23017), landmarkName: "Maracanã Stadium"),
        
        // EUROPE
        City(name: "London", coordinate: CLLocationCoordinate2D(latitude: 51.5560, longitude: -0.2795), landmarkName: "Wembley Stadium"),
        City(name: "Paris", coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945), landmarkName: "Eiffel Tower"),
        City(name: "Rome", coordinate: CLLocationCoordinate2D(latitude: 41.8902, longitude: 12.4922), landmarkName: "The Colosseum"),
        
        // AFRICA
        City(name: "Cairo", coordinate: CLLocationCoordinate2D(latitude: 30.068419, longitude: 31.312285), landmarkName: "Cairo International Stadium"),
        City(name: "Accra", coordinate: CLLocationCoordinate2D(latitude: 5.551051, longitude: -0.191801), landmarkName: "Accra Sports Stadium"),
        City(name: "Johannesburg", coordinate: CLLocationCoordinate2D(latitude: -26.2349, longitude: 27.9821), landmarkName: "FNB Stadium"),
        
        // ASIA
        City(name: "Tokyo", coordinate: CLLocationCoordinate2D(latitude: 35.6785, longitude: 139.7145), landmarkName: "Tokyo National Stadium"),
        City(name: "Dubai", coordinate: CLLocationCoordinate2D(latitude: 25.1972, longitude: 55.2744), landmarkName: "Burj Khalifa"),
        City(name: "Singapore", coordinate: CLLocationCoordinate2D(latitude: 1.3039, longitude: 103.8744), landmarkName: "Singapore National Stadium"),
        
        // AUSTRALIA
        City(name: "Sydney", coordinate: CLLocationCoordinate2D(latitude: -33.8917, longitude: 151.2247), landmarkName: "Sydney Cricket Ground"),
        City(name: "Melbourne", coordinate: CLLocationCoordinate2D(latitude: -37.8200, longitude: 144.9835), landmarkName: "Melbourne Cricket Ground"),
        City(name: "Brisbane", coordinate: CLLocationCoordinate2D(latitude: -27.4858, longitude: 153.0381), landmarkName: "The Gabba")
    ]
}

