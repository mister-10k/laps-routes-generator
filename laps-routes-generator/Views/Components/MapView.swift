import SwiftUI
import MapKit

// Custom annotation for starting point marker (race flag)
class StartingPointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    
    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String? = nil) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}

// Custom annotation for turnaround point marker
class TurnaroundPointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    
    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String? = nil) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}

struct MapView: NSViewRepresentable {
    let region: MKCoordinateRegion
    let startingPoint: StartingPoint?
    let selectedRoute: Route?
    
    init(region: MKCoordinateRegion, startingPoint: StartingPoint? = nil, selectedRoute: Route?) {
        self.region = region
        self.startingPoint = startingPoint
        self.selectedRoute = selectedRoute
    }
    
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = false
        mapView.showsScale = true
        mapView.showsCompass = true
        mapView.delegate = context.coordinator
        
        // Add click gesture recognizer to show coordinates
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapClick(_:)))
        mapView.addGestureRecognizer(clickGesture)
        
        return mapView
    }
    
    func updateNSView(_ nsView: MKMapView, context: Context) {
        // Update region
        nsView.setRegion(region, animated: true)
        
        // Update overlays
        nsView.removeOverlays(nsView.overlays)
        
        // Update annotations
        nsView.removeAnnotations(nsView.annotations)
        
        if let route = selectedRoute {
            // Add route path overlays
            let outbound = MKPolyline(coordinates: route.outboundPath, count: route.outboundPath.count)
            outbound.title = "Outbound"
            
            let inbound = MKPolyline(coordinates: route.returnPath, count: route.returnPath.count)
            inbound.title = "Return"
            
            nsView.addOverlays([outbound, inbound])
            
            // Add starting point marker (race flag) from route
            let startingAnnotation = StartingPointAnnotation(
                coordinate: route.startingPoint.coordinate,
                title: route.startingPoint.name,
                subtitle: "Start/Finish"
            )
            nsView.addAnnotation(startingAnnotation)
            
            // Add turnaround point marker
            let turnaroundAnnotation = TurnaroundPointAnnotation(
                coordinate: route.turnaroundPoint.coordinate,
                title: route.turnaroundPoint.name,
                subtitle: String(format: "%.1f mi round trip", route.totalDistanceMiles)
            )
            nsView.addAnnotation(turnaroundAnnotation)
        } else if let startingPoint = startingPoint {
            // No route selected - show just the starting point marker
            let startingAnnotation = StartingPointAnnotation(
                coordinate: startingPoint.coordinate,
                title: startingPoint.name,
                subtitle: "Start/Finish"
            )
            nsView.addAnnotation(startingAnnotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        @objc func handleMapClick(_ gesture: NSClickGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            
            let clickPoint = gesture.location(in: mapView)
            let coordinate = mapView.convert(clickPoint, toCoordinateFrom: mapView)
            
            print("📍 Map tapped at: \(coordinate.latitude), \(coordinate.longitude)")
            print("   Latitude: \(coordinate.latitude)")
            print("   Longitude: \(coordinate.longitude)")
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                
                switch polyline.title {
                case "Outbound":
                    renderer.strokeColor = .systemBlue
                    renderer.lineWidth = 4
                case "Return":
                    renderer.strokeColor = .systemGreen
                    renderer.lineWidth = 4
                default:
                    renderer.strokeColor = .gray
                    renderer.lineWidth = 3
                }
                
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Don't customize user location
            if annotation is MKUserLocation {
                return nil
            }
            
            // Starting point annotation - checkered race flag
            if let startingPoint = annotation as? StartingPointAnnotation {
                let identifier = "StartingPointMarker"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: startingPoint, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                } else {
                    annotationView?.annotation = startingPoint
                }
                
                // Green marker with checkered flag for start/finish
                annotationView?.markerTintColor = .systemGreen
                annotationView?.glyphImage = NSImage(systemSymbolName: "flag.checkered", accessibilityDescription: "Start/Finish")
                
                return annotationView
            }
            
            // Turnaround point annotation - red marker
            if let turnaroundPoint = annotation as? TurnaroundPointAnnotation {
                let identifier = "TurnaroundPointMarker"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: turnaroundPoint, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                } else {
                    annotationView?.annotation = turnaroundPoint
                }
                
                // Red marker for destination
                annotationView?.markerTintColor = .systemRed
                annotationView?.glyphImage = NSImage(systemSymbolName: "flag.fill", accessibilityDescription: "Destination")
                
                return annotationView
            }
            
            return nil
        }
    }
}
