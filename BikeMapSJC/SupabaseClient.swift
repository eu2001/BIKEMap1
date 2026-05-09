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

    enum CodingKeys: String, CodingKey {
        case id, username, avatar
        case contributionCount = "contribution_count"
        case isPremium = "is_premium"
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

    enum CodingKeys: String, CodingKey {
        case id, type, lat, lng, title, description
        case authorUsername = "author_username"
        case authorId = "author_id"
    }

    var asPOI: POI {
        POI(id: id, type: type, lat: lat, lng: lng,
            title: title, description: description,
            author: authorUsername)
    }
}
