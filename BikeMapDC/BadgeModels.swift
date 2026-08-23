import Foundation

// MARK: - Badge row (from public.badges)

struct BadgeRow: Codable, Identifiable, Hashable {
    let id: UUID
    var slug: String
    var fromUserId: UUID
    var toUserId: UUID
    var message: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, slug, message
        case fromUserId = "from_user_id"
        case toUserId   = "to_user_id"
        case createdAt  = "created_at"
    }

    var badge: Badge? { Badge.fromSlug(slug) }
}

// MARK: - Received-with-sender join
//
// Convenience wrapper so the profile screen can render "X sent you a
// badge" without a second query per row. Built client-side in AppState.

struct ReceivedBadge: Identifiable, Hashable {
    let row: BadgeRow
    let sender: DirectoryProfile?
    var id: UUID { row.id }
    var badge: Badge? { row.badge }
    var createdAt: Date? { row.createdAt }
    var message: String { row.message }
}
