import SwiftUI
import MapKit

// Custom annotation for midpoint marker
class MidpointAnnotation: NSObject, MKAnnotation {
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
    let selectedRoute: Route?
    
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = false
        mapView.showsScale = true
        mapView.showsCompass = true
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateNSView(_ nsView: MKMapView, context: Context) {
        nsView.setRegion(region, animated: true)
        
        // Update overlays
        nsView.removeOverlays(nsView.overlays)
        
        // Update annotations (midpoint marker)
        nsView.removeAnnotations(nsView.annotations)
        
        if let route = selectedRoute {
            // Add route path overlays
            let outbound = MKPolyline(coordinates: route.outboundPath, count: route.outboundPath.count)
            outbound.title = "Outbound"
            
            let inbound = MKPolyline(coordinates: route.returnPath, count: route.returnPath.count)
            inbound.title = "Return"
            
            nsView.addOverlays([outbound, inbound])
            
            // Add midpoint marker
            let midpointAnnotation = MidpointAnnotation(
                coordinate: route.midpoint.coordinate,
                title: route.midpoint.name,
                subtitle: String(format: "%.1f mi round trip", route.totalDistanceMiles)
            )
            nsView.addAnnotation(midpointAnnotation)
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
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.lineWidth = 4
                
                if polyline.title == "Outbound" {
                    renderer.strokeColor = .systemBlue
                } else if polyline.title == "Return" {
                    renderer.strokeColor = .systemGreen
                } else {
                    renderer.strokeColor = .gray
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
            
            // Midpoint annotation - red marker
            if let midpoint = annotation as? MidpointAnnotation {
                let identifier = "MidpointMarker"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: midpoint, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                } else {
                    annotationView?.annotation = midpoint
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
