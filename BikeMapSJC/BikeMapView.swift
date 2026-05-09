import SwiftUI
import MapKit

// MARK: - UIViewRepresentable

struct BikeMapView: UIViewRepresentable {
    @ObservedObject var appState: AppState

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false

        // Initial region: São José dos Campos
        let center = CLLocationCoordinate2D(latitude: -23.1794, longitude: -45.8869)
        mapView.setRegion(MKCoordinateRegion(center: center, span: .init(latitudeDelta: 0.12, longitudeDelta: 0.12)), animated: false)

        // Map tap for picking mode
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        context.coordinator.setupInfra()
        context.coordinator.mapView = mapView

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let c = context.coordinator
        c.syncInfra(mapView: mapView, visibility: appState.layerVisibility)
        c.syncPOIs(mapView: mapView, pois: appState.pois, visibility: appState.layerVisibility)

        if appState.shouldCenterOnUser {
            if let userCoord = mapView.userLocation.location?.coordinate {
                mapView.setCenter(userCoord, animated: true)
            }
            DispatchQueue.main.async { self.appState.shouldCenterOnUser = false }
        }
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    weak var mapView: MKMapView?
    var appState: AppState

    // Infra overlays, keyed by InfraType.rawValue
    private var infraPolylines: [String: [BikePolyline]] = [:]
    private var infraOnMap: Set<String> = []

    // POI annotations, keyed by poi.id
    private var poiAnnotations: [String: POIAnnotation] = [:]

    init(appState: AppState) { self.appState = appState }

    // MARK: Setup

    func setupInfra() {
        for feature in MapData.infraFeatures {
            let pl = BikePolyline(coordinates: feature.coordinates, count: feature.coordinates.count)
            pl.infraType = feature.type
            pl.featureName = feature.name
            pl.extensionKm = feature.extensionKm
            pl.reason = feature.reason
            pl.status = feature.status
            pl.forecast = feature.forecast
            infraPolylines[feature.type.rawValue, default: []].append(pl)
        }
    }

    // MARK: Sync methods

    func syncInfra(mapView: MKMapView, visibility: [String: Bool]) {
        for type in InfraType.allCases {
            let key = type.rawValue
            let shouldShow = visibility[key] ?? true
            let onMap = infraOnMap.contains(key)
            let polylines = infraPolylines[key] ?? []

            if shouldShow && !onMap {
                polylines.forEach { mapView.addOverlay($0, level: .aboveRoads) }
                infraOnMap.insert(key)
            } else if !shouldShow && onMap {
                polylines.forEach { mapView.removeOverlay($0) }
                infraOnMap.remove(key)
            }
        }
    }

    func syncPOIs(mapView: MKMapView, pois: [POI], visibility: [String: Bool]) {
        for poi in pois where poiAnnotations[poi.id] == nil {
            poiAnnotations[poi.id] = POIAnnotation(poi: poi)
        }

        let onMapIds = Set(mapView.annotations.compactMap { ($0 as? POIAnnotation)?.poi.id })

        for (poiId, ann) in poiAnnotations {
            let shouldShow = visibility[ann.poi.type] ?? true
            let onMap = onMapIds.contains(poiId)
            if shouldShow && !onMap {
                mapView.addAnnotation(ann)
            } else if !shouldShow && onMap {
                mapView.removeAnnotation(ann)
            }
        }
    }

    // MARK: Map tap

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView else { return }
        let point = gesture.location(in: mapView)
        let coord = mapView.convert(point, toCoordinateFrom: mapView)

        switch appState.mapPickingMode {
        case .addPoint:
            DispatchQueue.main.async {
                self.appState.pendingAddCoordinate = coord
                self.appState.mapPickingMode = nil
                self.appState.showAddPoint = true
            }
        case .none:
            break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        appState.mapPickingMode != nil
    }

    // MARK: MKMapViewDelegate – overlay renderer

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let bike = overlay as? BikePolyline {
            let r = MKPolylineRenderer(polyline: bike)
            r.strokeColor = bike.infraType.uiColor
            r.lineWidth   = bike.infraType.lineWidth
            r.alpha       = 0.88
            r.lineDashPattern = bike.infraType.dashPattern
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    // MARK: MKMapViewDelegate – annotation views

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }

        if let poiAnn = annotation as? POIAnnotation {
            let reuseId = "poi_\(poiAnn.poi.type)"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseId)
            view.annotation = annotation
            view.image = makeEmojiImage(poiAnn.poi.poiType.emoji, borderColor: poiAnn.poi.poiType.uiColor)
            view.canShowCallout = false; view.centerOffset = .zero
            return view
        }

        return nil
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        mapView.deselectAnnotation(annotation, animated: false)
        guard appState.mapPickingMode == nil else { return }
        if let poiAnn = annotation as? POIAnnotation {
            DispatchQueue.main.async { self.appState.selectedPOI = poiAnn.poi }
        }
    }

    // MARK: Emoji image helper

    private func makeEmojiImage(_ emoji: String, borderColor: UIColor = .systemRed) -> UIImage {
        let size: CGFloat = 40
        let borderWidth: CGFloat = 2.5
        let renderer = UIGraphicsImageRenderer(size: .init(width: size, height: size))
        return renderer.image { _ in
            let circle = UIBezierPath(ovalIn: .init(x: 0, y: 0, width: size, height: size))

            // White fill
            UIColor.white.setFill()
            circle.fill()

            // Coloured border
            borderColor.setStroke()
            circle.lineWidth = borderWidth
            circle.stroke()

            // Emoji
            let font = UIFont.systemFont(ofSize: size * 0.50)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = (emoji as NSString).size(withAttributes: attrs)
            let origin = CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2)
            (emoji as NSString).draw(at: origin, withAttributes: attrs)
        }
    }
}

