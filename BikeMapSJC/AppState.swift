import Foundation
import MapKit
import Combine
import Supabase
import UserNotifications

class AppState: ObservableObject {

    // MARK: - Auth

    @Published var currentUserName: String?
    @Published var currentUserId: UUID?
    @Published var currentProfile: ProfileRow?
    @Published var selectedBikeId: String? = UserDefaults.standard.string(forKey: "selectedBikeId") {
        didSet { UserDefaults.standard.set(selectedBikeId, forKey: "selectedBikeId") }
    }

    var selectedBike: BikeRow? {
        guard let id = selectedBikeId else { return nil }
        return bikes.first { $0.id.uuidString == id }
    }

    // MARK: - Data

    @Published var pois:           [POI]              = []
    @Published var bikes:          [BikeRow]          = []
    @Published var userPOIs:       [POI]              = []
    @Published var infraFeatures:  [BikeInfraFeature] = []

    // MARK: - Layer visibility

    @Published var layerVisibility: [String: Bool] = {
        var v: [String: Bool] = [:]
        let defaultOnInfra: Set<InfraType> = [.ciclovia, .ciclofaixa, .compartilhada]
        InfraType.allCases.forEach { v[$0.rawValue] = defaultOnInfra.contains($0) }
        let defaultOnPOI: Set<POIType> = [.paraciclo]
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
    @Published var showReportFurto   = false
    @Published var selectedPOI: POI?
    @Published var mapPickingMode: MapPickingMode?
    @Published var pendingAddCoordinate: CLLocationCoordinate2D?
    @Published var pendingPOIType: POIType?
    @Published var shouldCenterOnUser    = false
    @Published var notificationTargetPOI: POI? = nil
    @Published var zoomDelta: Double     = 0   // +1 = zoom in, -1 = zoom out

    // MARK: - Toast

    @Published var toastMessage: String?
    private var toastTimer: Timer?

    // MARK: - Realtime

    private var realtimeTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        Task { await restoreSession() }
        startFurtoListener()
    }

    deinit { realtimeTask?.cancel() }

    private func startFurtoListener() {
        realtimeTask = Task {
            let channel = supabase.channel("furto-alerts")
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "pois")
            await channel.subscribe()
            for await change in changes {
                guard case .insert(let action) = change else { continue }
                let record = action.record
                guard let type = record["type"]?.stringValue, type == "furto",
                      let authorId = record["author_id"]?.stringValue else { continue }
                // Don't notify the user who just reported it
                await MainActor.run {
                    if authorId != self.currentUserId?.uuidString {
                        self.showToast("🔓 Novo roubo de bicicleta reportado na região! Fique atento.")
                    }
                }
            }
        }
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
                self.pois          = []
                self.bikes         = []
                self.userPOIs      = []
                self.selectedBikeId = nil
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

    func updateProfile(username: String, avatar: String) async throws {
        guard let userId = currentUserId else { return }
        try await supabase
            .from("profiles")
            .update(["username": username, "avatar": avatar])
            .eq("id", value: userId)
            .execute()
        await MainActor.run {
            self.currentProfile?.username = username
            self.currentProfile?.avatar   = avatar
            self.currentUserName          = username
        }
    }

    // MARK: - POIs

    func fetchPOIs() async {
        do {
            let rows: [POIRow] = try await supabase
                .from("pois")
                .select()
                .eq("status", value: "approved")
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
                         title: title, description: description, author: userName,
                         createdAt: Date())

        Task {
            do {
                struct InsertRow: Encodable {
                    let id, type, title, description, status: String
                    let lat, lng: Double
                    let authorUsername: String
                    let authorId: UUID
                    enum CodingKeys: String, CodingKey {
                        case id, type, title, description, status, lat, lng
                        case authorUsername = "author_username"
                        case authorId = "author_id"
                    }
                }
                // All user submissions start as "pending" — admin must approve before appearing on map
                let status = "pending"
                try await supabase.from("pois").insert(
                    InsertRow(id: id, type: type.rawValue, title: title,
                              description: description, status: status,
                              lat: coordinate.latitude, lng: coordinate.longitude,
                              authorUsername: userName, authorId: userId)
                ).execute()

                await MainActor.run {
                    showToast("✅ Ponto enviado! Será verificado pelo administrador antes de aparecer no mapa.")
                }

                // Notify admin immediately if this is a furto report
                if type == .furto {
                    try? await supabase.functions.invoke(
                        "notify-admin-furto",
                        options: .init(body: [
                            "poi_id":          id,
                            "title":           title,
                            "description":     description,
                            "lat":             String(coordinate.latitude),
                            "lng":             String(coordinate.longitude),
                            "author":          userName
                        ])
                    )
                }
            } catch {
                await MainActor.run {
                    showToast("❌ Erro ao salvar ponto. Tente novamente.")
                }
            }
        }
    }

    // MARK: - User POIs

    func fetchUserPOIs() async {
        guard let userId = currentUserId else { return }
        do {
            let rows: [POIRow] = try await supabase
                .from("pois")
                .select()
                .eq("author_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            await MainActor.run { self.userPOIs = rows.map(\.asPOI) }
        } catch {
            print("fetchUserPOIs error: \(error)")
        }
    }

    // MARK: - Bikes

    func fetchBikes() async {
        guard let userId = currentUserId else { return }
        do {
            let rows: [BikeRow] = try await supabase
                .from("bikes")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            await MainActor.run { self.bikes = rows }
        } catch {
            print("fetchBikes error: \(error)")
        }
    }

    func addBike(nickname: String, brand: String, color: String, aro: String,
                 serialNumber: String, details: String, imageData: Data?) async throws {
        guard let userId = currentUserId else { return }

        var imageUrl: String? = nil
        if let imageData { imageUrl = await uploadBikePhoto(imageData) }

        struct InsertBike: Encodable {
            let user_id: UUID
            let nickname, brand, color, aro, serial_number, details: String
            let image_url: String?
        }
        let inserted: BikeRow = try await supabase
            .from("bikes")
            .insert(InsertBike(user_id: userId, nickname: nickname, brand: brand,
                               color: color, aro: aro, serial_number: serialNumber,
                               details: details, image_url: imageUrl))
            .select()
            .single()
            .execute()
            .value
        await MainActor.run { self.bikes.insert(inserted, at: 0) }
    }

    func updateBike(_ bike: BikeRow, imageData: Data?) async throws {
        var imageUrl = bike.imageUrl
        if let imageData { imageUrl = await uploadBikePhoto(imageData) }

        struct UpdateBike: Encodable {
            let nickname, brand, color, aro, serial_number, details: String
            let image_url: String?
        }
        let updated: BikeRow = try await supabase
            .from("bikes")
            .update(UpdateBike(nickname: bike.nickname, brand: bike.brand,
                               color: bike.color, aro: bike.aro,
                               serial_number: bike.serialNumber,
                               details: bike.details, image_url: imageUrl))
            .eq("id", value: bike.id)
            .select()
            .single()
            .execute()
            .value
        await MainActor.run {
            if let idx = self.bikes.firstIndex(where: { $0.id == bike.id }) {
                self.bikes[idx] = updated
            }
        }
    }

    func deleteBike(_ bike: BikeRow) async throws {
        try await supabase.from("bikes").delete().eq("id", value: bike.id).execute()
        await MainActor.run { self.bikes.removeAll { $0.id == bike.id } }
    }

    private func uploadBikePhoto(_ data: Data) async -> String? {
        let fileName = "bike_\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try await supabase.storage
                .from("bike-photos")
                .upload(fileName, data: data, options: .init(contentType: "image/jpeg", upsert: false))
            let url = try supabase.storage.from("bike-photos").getPublicURL(path: fileName)
            return url.absoluteString
        } catch {
            print("uploadBikePhoto error: \(error)")
            return nil
        }
    }

    // MARK: - Photo Upload

    func uploadFurtoPhoto(_ data: Data) async -> String? {
        let fileName = "furto_\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try await supabase.storage
                .from("furto-photos")
                .upload(fileName, data: data, options: .init(contentType: "image/jpeg", upsert: false))
            let url = try supabase.storage
                .from("furto-photos")
                .getPublicURL(path: fileName)
            return url.absoluteString
        } catch {
            print("uploadFurtoPhoto error: \(error)")
            return nil
        }
    }

    // MARK: - Infrastructure Features

    func fetchInfraFeatures() async {
        do {
            struct InfraRow: Decodable {
                let name: String
                let type: String
                let coordinates: [[Double]]  // [[lng, lat], ...]
                let extensionKm: String?
                let reason: String?
                let status: String?
                let forecast: String?
                enum CodingKeys: String, CodingKey {
                    case name, type, coordinates
                    case extensionKm  = "extension_km"
                    case reason, status, forecast
                }
            }
            let rows: [InfraRow] = try await supabase
                .from("infra_features")
                .select()
                .execute()
                .value

            let features = rows.compactMap { row -> BikeInfraFeature? in
                guard let infraType = InfraType(rawValue: row.type) else { return nil }
                let coords = row.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
                }
                return BikeInfraFeature(
                    name: row.name, type: infraType,
                    coordinates: coords,
                    extensionKm: row.extensionKm,
                    reason: row.reason,
                    status: row.status,
                    forecast: row.forecast
                )
            }
            await MainActor.run {
                self.infraFeatures = features
            }
        } catch {
            // Fallback to hardcoded data if Supabase is unreachable
            await MainActor.run {
                if self.infraFeatures.isEmpty {
                    self.infraFeatures = MapData.infraFeatures
                }
            }
            print("fetchInfraFeatures error: \(error)")
        }
    }

    // MARK: - Admin

    var isAdmin: Bool { currentProfile?.isAdmin == true }

    func fetchPendingPOIs() async -> [POI] {
        do {
            let rows: [POIRow] = try await supabase
                .from("pois")
                .select()
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows.map { $0.asPOI }
        } catch {
            print("fetchPendingPOIs error: \(error)")
            return []
        }
    }

    func approvePOI(_ poi: POI) async throws {
        try await supabase
            .from("pois")
            .update(["status": "approved"])
            .eq("id", value: poi.id)
            .execute()
        await MainActor.run {
            if !self.pois.contains(where: { $0.id == poi.id }) {
                self.pois.append(poi)
            }
            showToast("✅ Ponto aprovado e publicado no mapa.")
        }

        // Notify all users only after admin approves a furto
        if poi.poiType == .furto {
            try? await supabase.functions.invoke(
                "notify-users-furto",
                options: .init(body: [
                    "poi_id":      poi.id,
                    "title":       poi.title,
                    "description": poi.description,
                    "lat":         String(poi.lat),
                    "lng":         String(poi.lng)
                ])
            )
        }
    }

    func rejectPOI(_ poi: POI) async throws {
        try await supabase
            .from("pois")
            .update(["status": "rejected"])
            .eq("id", value: poi.id)
            .execute()
        await MainActor.run {
            showToast("🗑️ Ponto rejeitado.")
        }
    }

    // MARK: - Push Notifications

    func requestPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func savePushToken(_ token: String) {
        Task {
            do {
                struct TokenRow: Encodable {
                    let token: String
                    let platform: String
                    let userId: UUID?
                    enum CodingKeys: String, CodingKey {
                        case token, platform
                        case userId = "user_id"
                    }
                }
                try await supabase
                    .from("push_tokens")
                    .upsert(TokenRow(token: token, platform: "ios", userId: currentUserId),
                            onConflict: "token")
                    .execute()
            } catch {
                print("savePushToken error: \(error)")
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
