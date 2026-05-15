import CoreLocation

/// Geographic boundary used to validate points before adding them.
/// Matches the DC-metro bounding box used by the OSM / DCGIS importers
/// (covers DC, Arlington, Alexandria, Falls Church, inner Fairfax/MoCo/PG counties).
enum DCBounds {
    private static let minLat: Double =  38.50
    private static let maxLat: Double =  39.20
    private static let minLon: Double = -77.55
    private static let maxLon: Double = -76.70

    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude  >= minLat &&
        coordinate.latitude  <= maxLat &&
        coordinate.longitude >= minLon &&
        coordinate.longitude <= maxLon
    }

    static let outOfBoundsMessage =
        "This point is outside the Washington, DC metro area. Only points within the city and inner suburbs can be added."
}
