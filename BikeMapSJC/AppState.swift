import Foundation
import MapKit
import Combine
import Supabase

class AppState: ObservableObject {

    // MARK: - Auth

    @Published var currentUserName: String?
    @Published var currentUserId: UUID?
    @Published var currentProfile: ProfileRow?

    // MARK: - Data

    @Published var pois: [POI] = []

    // MARK: - Layer visibility

    @Published var layerVisibility: [String: Bool] = {
        var v: [String: Bool] = [:]
        let defaultOnInfra: Set<InfraType> = [.ciclovia, .ciclofaixa]
        InfraType.allCases.forEach { v[$0.rawValue] = defaultOnInfra.contains($0) }
        let defaultOnPOI: Set<POIType> = [.paraciclo, .bike_sharing]
        POIType.allCases.forEach { v[$0.rawValue] = defaultOnPOI.contains($0) }
        return v
    }()

    // MARK: - UI state

    @Published var guestAccess       = false
    @Published var showSidebar       = false
    @Published var showLegend        = false
    @Published var showRanking       = false
    @Published var showAuth          = false
    @Published var showAddPoint      = false
    @Published var selectedPOI: POI?
    @Published var mapPickingMode: MapPickingMode?
    @Published var pendingAddCoordinate: CLLocationCoordinate2D?
    @Published var shouldCenterOnUser = false

    // MARK: - Toast

    @Published var toastMessage: String?
    private var toastTimer: Timer?

    // MARK: - Init

    init() {
        Task { await restoreSession() }
    }

    // MARK: - Session restore

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            await MainActor.run {
                self.currentUserId = session.user.id
            }
            await fetchProfile(userId: session.user.id)
        } catch {
            // No active session — show welcome screen
        }
        // Always load POIs — the table is publicly readable
        await fetchPOIs()
    }

    // MARK: - Auth

    func register(email: String, password: String, username: String, avatar: String) async throws {
        // Call edge function so we can validate username uniqueness server-side
        struct RegisterBody: Encodable {
            let email, password, username, avatar: String
        }
        struct RegisterResponse: Decodable {
            let error: String?
        }

        let url = URL(string: "https://rwhwngayniazpruukblm.supabase.co/functions/v1/register-user")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(RegisterBody(email: email, password: password,
                                                             username: username, avatar: avatar))
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 201 {
            let body = try JSONDecoder().decode(RegisterResponse.self, from: data)
            throw AppError.message(body.error ?? "Erro ao criar conta.")
        }

        // Now sign in
        try await signIn(email: email, password: password)
        await MainActor.run { showToast("🎉 Conta criada! Bem-vindo(a), \(username)!") }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        await MainActor.run { self.currentUserId = session.user.id }
        await fetchProfile(userId: session.user.id)
        await fetchPOIs()
    }

    func logout() {
        Task {
            try? await supabase.auth.signOut()
            await MainActor.run {
                self.currentUserName = nil
                self.currentUserId = nil
                self.currentProfile = nil
                self.guestAccess = false
                self.pois = []
                showToast("Você saiu da conta. 👋")
            }
        }
    }

    // MARK: - Profile

    func fetchProfile(userId: UUID) async {
        do {
            let profile: ProfileRow = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            await MainActor.run {
                self.currentProfile = profile
                self.currentUserName = profile.username
            }
        } catch {
            print("fetchProfile error: \(error)")
        }
    }

    var currentUser: ProfileRow? { currentProfile }

    // MARK: - POIs

    func fetchPOIs() async {
        do {
            let rows: [POIRow] = try await supabase
                .from("pois")
                .select()
                .execute()
                .value
            await MainActor.run {
                self.pois = rows.map(\.asPOI)
            }
        } catch {
            print("fetchPOIs error: \(error)")
            // Fall back to local seed data
            await MainActor.run {
                if self.pois.isEmpty { self.pois = MapData.initialPOIs }
            }
        }
    }

    func addPOI(type: POIType, coordinate: CLLocationCoordinate2D,
                title: String, description: String) {
        guard let userId = currentUserId,
              let userName = currentUserName else { return }

        let id = "u_\(Int(Date().timeIntervalSince1970))"
        let newPOI = POI(id: id, type: type.rawValue,
                         lat: coordinate.latitude, lng: coordinate.longitude,
                         title: title, description: description, author: userName)

        Task {
            do {
                struct InsertRow: Encodable {
                    let id, type, title, description: String
                    let lat, lng: Double
                    let authorUsername: String
                    let authorId: UUID
                    enum CodingKeys: String, CodingKey {
                        case id, type, title, description, lat, lng
                        case authorUsername = "author_username"
                        case authorId = "author_id"
                    }
                }
                try await supabase.from("pois").insert(
                    InsertRow(id: id, type: type.rawValue, title: title,
                              description: description, lat: coordinate.latitude,
                              lng: coordinate.longitude, authorUsername: userName,
                              authorId: userId)
                ).execute()

                await MainActor.run {
                    self.pois.append(newPOI)
                    // Optimistically bump count
                    self.currentProfile?.contributionCount += 1
                    showToast("✅ Ponto adicionado! Obrigado pela contribuição.")
                }
            } catch {
                await MainActor.run {
                    showToast("❌ Erro ao salvar ponto. Tente novamente.")
                }
            }
        }
    }

    // MARK: - Ranking

    func rankedUsers() async -> [(username: String, profile: ProfileRow)] {
        do {
            let profiles: [ProfileRow] = try await supabase
                .from("profiles")
                .select()
                .order("contribution_count", ascending: false)
                .limit(50)
                .execute()
                .value
            return profiles.map { (username: $0.username, profile: $0) }
        } catch {
            return []
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastMessage = message
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.toastMessage = nil }
        }
    }
}

// MARK: - App errors

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}
