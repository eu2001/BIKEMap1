import CoreLocation

/// Geographic boundary of the municipality of São José dos Campos, SP.
/// Source: approximate bounding box of the official municipal limits.
enum SJCBounds {
    // Municipality bounding box
    private static let minLat: Double = -23.45
    private static let maxLat: Double = -22.90
    private static let minLon: Double = -46.10
    private static let maxLon: Double = -45.45

    /// Returns `true` if the coordinate falls within SJC's municipal limits.
    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude  >= minLat &&
        coordinate.latitude  <= maxLat &&
        coordinate.longitude >= minLon &&
        coordinate.longitude <= maxLon
    }

    static let outOfBoundsMessage =
        "Este ponto está fora dos limites de São José dos Campos. Apenas pontos dentro do município podem ser adicionados."
}
