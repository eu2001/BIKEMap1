import Foundation
import CoreLocation

// MARK: - Visibility

enum RideVisibility: String, Codable, CaseIterable, Identifiable {
    case privateOnly = "private"
    case friends     = "friends"
    case publicToAll = "public"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .privateOnly: return "Only me"
        case .friends:     return "Friends"
        case .publicToAll: return "Public"
        }
    }
    var systemImage: String {
        switch self {
        case .privateOnly: return "lock.fill"
        case .friends:     return "person.2.fill"
        case .publicToAll: return "globe"
        }
    }
}

// MARK: - Row types

struct RideRow: Codable, Identifiable, Hashable {
    let id: UUID
    var userId: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date
    var distanceM: Double
    var durationS: Int
    var visibility: String              // matches RideVisibility.rawValue
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, visibility
        case userId     = "user_id"
        case startedAt  = "started_at"
        case endedAt    = "ended_at"
        case distanceM  = "distance_m"
        case durationS  = "duration_s"
        case createdAt  = "created_at"
    }

    var visibilityEnum: RideVisibility {
        RideVisibility(rawValue: visibility) ?? .friends
    }

    // Pretty distance/pace helpers for the UI
    var distanceKm: Double { distanceM / 1000.0 }
    var distanceMi: Double { distanceM / 1609.344 }

    var averageSpeedKmh: Double {
        durationS > 0 ? (distanceM / Double(durationS)) * 3.6 : 0
    }
    var averageSpeedMph: Double { averageSpeedKmh * 0.621371 }

    var formattedDuration: String {
        let s = durationS
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    /// Fallback title if the user didn't name the ride.
    var displayTitle: String {
        title.isEmpty ? startedAt.formatted(date: .abbreviated, time: .shortened) : title
    }
}

struct RidePoint: Codable, Hashable {
    var rideId: UUID?
    var seq: Int
    var lat: Double
    var lng: Double
    var speedMps: Double?
    var ts: Date

    enum CodingKeys: String, CodingKey {
        case seq, lat, lng, ts
        case rideId    = "ride_id"
        case speedMps  = "speed_mps"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Distance math

enum RideMath {
    /// Great-circle distance between two coordinates, meters (Haversine).
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0
        let lat1 = a.latitude  * .pi / 180
        let lat2 = b.latitude  * .pi / 180
        let dLat = (b.latitude  - a.latitude)  * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat/2)*sin(dLat/2) + cos(lat1)*cos(lat2)*sin(dLon/2)*sin(dLon/2)
        return 2 * R * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Sum of segment lengths along an ordered trail.
    static func totalDistance(_ points: [CLLocationCoordinate2D]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += distance(points[i-1], points[i])
        }
        return total
    }
}
