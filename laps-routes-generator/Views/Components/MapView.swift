import SwiftUI
import MapKit

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
        
        if let route = selectedRoute {
            let outbound = MKPolyline(coordinates: route.outboundPath, count: route.outboundPath.count)
            outbound.title = "Outbound"
            
            let inbound = MKPolyline(coordinates: route.returnPath, count: route.returnPath.count)
            inbound.title = "Return"
            
            nsView.addOverlays([outbound, inbound])
            
            // Optionally adjust visible rect to fit route
            // let rect = outbound.boundingMapRect.union(inbound.boundingMapRect)
            // nsView.setVisibleMapRect(rect, edgePadding: NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), animated: true)
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
    }
}
