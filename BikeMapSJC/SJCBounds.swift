import CoreLocation

/// Geographic boundary used to validate points before adding them.
/// Source: approximate bounding box of the city limits.
enum SJCBounds {
    // City bounding box
    private static let minLat: Double = -23.45
    private static let maxLat: Double = -22.90
    private static let minLon: Double = -46.10
    private static let maxLon: Double = -45.45

    /// Returns `true` if the coordinate falls within the city limits.
    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude  >= minLat &&
        coordinate.latitude  <= maxLat &&
        coordinate.longitude >= minLon &&
        coordinate.longitude <= maxLon
    }

    static let outOfBoundsMessage =
        "This point is outside the Washington, DC area. Only points within the city limits can be added."
}
