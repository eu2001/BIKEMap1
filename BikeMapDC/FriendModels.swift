import Foundation

// MARK: - Friend row (from the my_friends view)
//
// One row per accepted friendship of the current user, resolved to the
// OTHER party's profile fields (never the caller themselves).

struct FriendRow: Codable, Identifiable, Hashable {
    let requestId: UUID
    let friendId: UUID
    var since: Date?
    var username: String
    var avatar: String
    var contributionCount: Int
    var isPremium: Bool

    // Identifiable — friendId is unique per friend for the current user.
    var id: UUID { friendId }

    enum CodingKeys: String, CodingKey {
        case requestId          = "request_id"
        case friendId           = "friend_id"
        case since
        case username, avatar
        case contributionCount  = "contribution_count"
        case isPremium          = "is_premium"
    }
}


// MARK: - Friend request row (raw table row)
//
// One per row in public.friend_requests. The UI joins these with profile
// lookups on both requester_id and addressee_id to render usernames/avatars.

struct FriendRequestRow: Codable, Identifiable, Hashable {
    let id: UUID
    var requesterId: UUID
    var addresseeId: UUID
    var status: String            // pending | accepted | rejected | cancelled
    var createdAt: Date?
    var respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterId  = "requester_id"
        case addresseeId  = "addressee_id"
        case createdAt    = "created_at"
        case respondedAt  = "responded_at"
    }

    // Given the current user's id, return the other party.
    func otherParty(from selfId: UUID) -> UUID {
        selfId == requesterId ? addresseeId : requesterId
    }

    // Is the current user the one who sent this request?
    func isOutgoing(from selfId: UUID) -> Bool {
        requesterId == selfId
    }
}


// MARK: - Directory row
//
// Lightweight profile used by AddFriendView's search results and the
// FriendRequestRowView header (so we don't have to re-fetch each time).

struct DirectoryProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String
    var avatar: String
    var contributionCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, avatar
        case contributionCount = "contribution_count"
    }
}
