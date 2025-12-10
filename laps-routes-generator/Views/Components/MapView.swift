import SwiftUI
import MapKit

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

// Custom annotation for forbidden path drawing points
class ForbiddenPathPointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let index: Int
    var title: String? { "Point \(index + 1)" }
    
    init(coordinate: CLLocationCoordinate2D, index: Int) {
        self.coordinate = coordinate
        self.index = index
        super.init()
    }
}

struct MapView: NSViewRepresentable {
    let region: MKCoordinateRegion
    let selectedRoute: Route?
    let forbiddenPaths: [ForbiddenPath]
    let isDrawingForbiddenPath: Bool
    @Binding var currentDrawingPoints: [CLLocationCoordinate2D]
    
    init(region: MKCoordinateRegion, selectedRoute: Route?, forbiddenPaths: [ForbiddenPath] = [], isDrawingForbiddenPath: Bool = false, currentDrawingPoints: Binding<[CLLocationCoordinate2D]> = .constant([])) {
        self.region = region
        self.selectedRoute = selectedRoute
        self.forbiddenPaths = forbiddenPaths
        self.isDrawingForbiddenPath = isDrawingForbiddenPath
        self._currentDrawingPoints = currentDrawingPoints
    }
    
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = false
        mapView.showsScale = true
        mapView.showsCompass = true
        mapView.delegate = context.coordinator
        
        // Add click gesture recognizer for forbidden path drawing
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapClick(_:)))
        mapView.addGestureRecognizer(clickGesture)
        
        return mapView
    }
    
    func updateNSView(_ nsView: MKMapView, context: Context) {
        // Update coordinator's reference to parent
        context.coordinator.parent = self
        
        // Only update region if it actually changed (avoid re-centering during drawing)
        let currentCenter = nsView.region.center
        let currentSpan = nsView.region.span
        let regionChanged = abs(currentCenter.latitude - region.center.latitude) > 0.0001 ||
                           abs(currentCenter.longitude - region.center.longitude) > 0.0001 ||
                           abs(currentSpan.latitudeDelta - region.span.latitudeDelta) > 0.001 ||
                           abs(currentSpan.longitudeDelta - region.span.longitudeDelta) > 0.001
        
        if regionChanged {
            nsView.setRegion(region, animated: true)
        }
        
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
            
            // Add turnaround point marker
            let turnaroundAnnotation = TurnaroundPointAnnotation(
                coordinate: route.turnaroundPoint.coordinate,
                title: route.turnaroundPoint.name,
                subtitle: String(format: "%.1f mi round trip", route.totalDistanceMiles)
            )
            nsView.addAnnotation(turnaroundAnnotation)
        }
        
        // Add saved forbidden paths (red dashed lines)
        for path in forbiddenPaths {
            var coords = path.clCoordinates
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            polyline.title = "Forbidden"
            nsView.addOverlay(polyline)
        }
        
        // Add current drawing path (orange line while drawing)
        if isDrawingForbiddenPath && currentDrawingPoints.count > 1 {
            var coords = currentDrawingPoints
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            polyline.title = "Drawing"
            nsView.addOverlay(polyline)
        }
        
        // Add drawing point markers
        if isDrawingForbiddenPath {
            for (index, coord) in currentDrawingPoints.enumerated() {
                let annotation = ForbiddenPathPointAnnotation(coordinate: coord, index: index)
                nsView.addAnnotation(annotation)
            }
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
        
        @objc func handleMapClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            guard parent.isDrawingForbiddenPath else { return }
            
            guard let mapView = gestureRecognizer.view as? MKMapView else { return }
            
            let locationInView = gestureRecognizer.location(in: mapView)
            let coordinate = mapView.convert(locationInView, toCoordinateFrom: mapView)
            
            // Add point to current drawing
            parent.currentDrawingPoints.append(coordinate)
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
                case "Forbidden":
                    renderer.strokeColor = .systemRed
                    renderer.lineWidth = 5
                    renderer.lineDashPattern = [10, 5]
                case "Drawing":
                    renderer.strokeColor = .systemOrange
                    renderer.lineWidth = 4
                    renderer.lineDashPattern = [5, 3]
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
            
            // Forbidden path drawing point annotation - orange circle
            if let drawingPoint = annotation as? ForbiddenPathPointAnnotation {
                let identifier = "ForbiddenPathPoint"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: drawingPoint, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                } else {
                    annotationView?.annotation = drawingPoint
                }
                
                annotationView?.markerTintColor = .systemOrange
                annotationView?.glyphText = "\(drawingPoint.index + 1)"
                annotationView?.displayPriority = .required
                
                return annotationView
            }
            
            return nil
        }
    }
}
