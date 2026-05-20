import Foundation
import Supabase

// MARK: - Shared client

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://rwhwngayniazpruukblm.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ3aHduZ2F5bmlhenBydXVrYmxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyNDc5MDYsImV4cCI6MjA5MzgyMzkwNn0.ZxJKC-Qfpp9R7mw1tPxEkVYesFA2EgWgJOwJysplxX0"
)

// MARK: - Database row types

struct ProfileRow: Codable {
    let id: UUID
    var username: String
    var avatar: String
    var contributionCount: Int
    var isPremium: Bool
    var isAdmin: Bool
    var isBlocked: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, avatar
        case contributionCount = "contribution_count"
        case isPremium = "is_premium"
        case isAdmin   = "is_admin"
        case isBlocked = "is_blocked"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,   forKey: .id)
        username          = try c.decode(String.self, forKey: .username)
        avatar            = try c.decode(String.self, forKey: .avatar)
        contributionCount = try c.decode(Int.self,    forKey: .contributionCount)
        isPremium         = try c.decode(Bool.self,   forKey: .isPremium)
        isAdmin           = try c.decode(Bool.self,   forKey: .isAdmin)
        isBlocked         = (try? c.decode(Bool.self, forKey: .isBlocked)) ?? false
    }
}

struct BikeRow: Codable, Identifiable, Hashable {
    let id: UUID
    var userId: UUID
    var nickname: String
    var brand: String
    var color: String
    var aro: String
    var serialNumber: String
    var details: String
    var imageUrl: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId       = "user_id"
        case nickname, brand, color, aro, details
        case serialNumber = "serial_number"
        case imageUrl     = "image_url"
        case createdAt    = "created_at"
    }
}

struct POIRow: Codable, Identifiable {
    let id: String
    var type: String
    var lat: Double
    var lng: Double
    var title: String
    var description: String
    var authorUsername: String
    var authorId: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, lat, lng, title, description
        case authorUsername = "author_username"
        case authorId       = "author_id"
        case createdAt      = "created_at"
    }

    var asPOI: POI {
        POI(id: id, type: type, lat: lat, lng: lng,
            title: title, description: description,
            author: authorUsername, createdAt: createdAt)
    }
}
