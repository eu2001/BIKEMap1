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
    @Published var notifications:  [NotificationRow]  = []

    // Friends state
    @Published var friends:          [FriendRow]                                  = []
    @Published var incomingRequests: [(FriendRequestRow, DirectoryProfile)]       = []
    @Published var outgoingRequests: [(FriendRequestRow, DirectoryProfile)]       = []

    // Rides state
    @Published var rides: [RideRow] = []

    // Badges the current user has received
    @Published var receivedBadges: [ReceivedBadge] = []

    var unreadNotificationCount: Int { notifications.filter { !$0.isRead }.count }

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
    private var notificationsTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        Task { await restoreSession() }
        startFurtoListener()
    }

    deinit {
        realtimeTask?.cancel()
        notificationsTask?.cancel()
    }

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
                        self.showToast("🔓 New bike theft reported nearby! Stay alert.")
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
            await fetchNotifications()
            startNotificationsListener()
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

        let url = URL(string: "https://hobulqkujiczaakaucwz.supabase.co/functions/v1/register-user")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(RegisterBody(email: email, password: password,
                                                             username: username, avatar: avatar))
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 201 {
            let body = try JSONDecoder().decode(RegisterResponse.self, from: data)
            throw AppError.message(body.error ?? "Error creating account.")
        }

        // Now sign in
        try await signIn(email: email, password: password)
        await MainActor.run { showToast("🎉 Account created! Welcome, \(username)!") }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        await MainActor.run { self.currentUserId = session.user.id }
        await fetchProfile(userId: session.user.id)
        await fetchPOIs()
        await fetchNotifications()
        startNotificationsListener()
    }

    func logout() {
        Task {
            try? await supabase.auth.signOut()
            notificationsTask?.cancel()
            notificationsTask = nil
            await MainActor.run {
                self.currentUserName = nil
                self.currentUserId = nil
                self.currentProfile = nil
                self.guestAccess = false
                self.pois          = []
                self.bikes         = []
                self.userPOIs      = []
                self.notifications = []
                self.selectedBikeId = nil
                showToast("You've been signed out. 👋")
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
                    showToast("✅ Point submitted! It will be reviewed by an admin before appearing on the map.")
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
                    showToast("❌ Error saving point. Try again.")
                }
            }
        }
    }

    // MARK: - Friends

    func refreshFriendState() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchFriends() }
            group.addTask { await self.fetchFriendRequests() }
        }
    }

    func fetchFriends() async {
        guard currentUserId != nil else { return }
        do {
            let rows: [FriendRow] = try await supabase
                .from("my_friends")
                .select()
                .order("username", ascending: true)
                .execute()
                .value
            await MainActor.run { self.friends = rows }
        } catch {
            print("fetchFriends error: \(error)")
        }
    }

    func fetchFriendRequests() async {
        guard let uid = currentUserId else { return }
        do {
            let rows: [FriendRequestRow] = try await supabase
                .from("friend_requests")
                .select()
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value

            // Split by direction; look up the OTHER party's profile once per unique id.
            let incoming = rows.filter { $0.addresseeId == uid }
            let outgoing = rows.filter { $0.requesterId == uid }
            let profileIds = Set(incoming.map(\.requesterId) + outgoing.map(\.addresseeId))
            let profiles = try await fetchDirectoryProfiles(ids: Array(profileIds))
            let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

            let inPairs  = incoming.compactMap { req in
                byId[req.requesterId].map { (req, $0) }
            }
            let outPairs = outgoing.compactMap { req in
                byId[req.addresseeId].map { (req, $0) }
            }
            await MainActor.run {
                self.incomingRequests = inPairs
                self.outgoingRequests = outPairs
            }
        } catch {
            print("fetchFriendRequests error: \(error)")
        }
    }

    private func fetchDirectoryProfiles(ids: [UUID]) async throws -> [DirectoryProfile] {
        guard !ids.isEmpty else { return [] }
        return try await supabase
            .from("profiles")
            .select("id, username, avatar, contribution_count")
            .in("id", values: ids.map { $0.uuidString })
            .execute()
            .value
    }

    func searchProfiles(byUsername query: String) async throws -> [DirectoryProfile] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return try await supabase
            .from("profiles")
            .select("id, username, avatar, contribution_count")
            .ilike("username", pattern: "%\(q)%")
            .order("contribution_count", ascending: false)
            .limit(20)
            .execute()
            .value
    }

    func sendFriendRequest(to addressee: UUID) async throws {
        guard let uid = currentUserId else {
            throw AppError.message("Sign in to add friends.")
        }
        guard uid != addressee else {
            throw AppError.message("You can't friend yourself.")
        }
        struct Insert: Encodable {
            let requester_id: UUID
            let addressee_id: UUID
        }
        try await supabase.from("friend_requests")
            .insert(Insert(requester_id: uid, addressee_id: addressee))
            .execute()
        await fetchFriendRequests()
    }

    func respondToFriendRequest(_ request: FriendRequestRow, accept: Bool) async throws {
        let status = accept ? "accepted" : "rejected"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try await supabase.from("friend_requests")
            .update([
                "status": status,
                "responded_at": formatter.string(from: Date())
            ])
            .eq("id", value: request.id)
            .execute()
        await refreshFriendState()
    }

    func cancelFriendRequest(_ request: FriendRequestRow) async throws {
        try await supabase.from("friend_requests")
            .delete().eq("id", value: request.id).execute()
        await fetchFriendRequests()
    }

    func removeFriend(_ friend: FriendRow) async throws {
        try await supabase.from("friend_requests")
            .delete().eq("id", value: friend.requestId).execute()
        await MainActor.run { self.friends.removeAll { $0.friendId == friend.friendId } }
    }

    // MARK: - Badges

    func sendBadge(to userId: UUID, slug: String, message: String) async throws {
        guard let uid = currentUserId else {
            throw AppError.message("Sign in to send badges.")
        }
        guard uid != userId else {
            throw AppError.message("Can't send a badge to yourself.")
        }
        struct InsertBadge: Encodable {
            let from_user_id: UUID
            let to_user_id: UUID
            let slug: String
            let message: String
        }
        try await supabase.from("badges").insert(
            InsertBadge(from_user_id: uid, to_user_id: userId,
                        slug: slug, message: message)
        ).execute()
    }

    func fetchReceivedBadges() async {
        guard let uid = currentUserId else { return }
        do {
            let rows: [BadgeRow] = try await supabase
                .from("badges")
                .select()
                .eq("to_user_id", value: uid)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value

            // Resolve senders in one lookup for efficiency
            let senderIds = Set(rows.map(\.fromUserId))
            let senders = try await fetchDirectoryProfiles(ids: Array(senderIds))
            let byId = Dictionary(uniqueKeysWithValues: senders.map { ($0.id, $0) })

            let joined = rows.map { r in
                ReceivedBadge(row: r, sender: byId[r.fromUserId])
            }
            await MainActor.run { self.receivedBadges = joined }
        } catch {
            print("fetchReceivedBadges error: \(error)")
        }
    }

    func removeReceivedBadge(_ badge: BadgeRow) async throws {
        try await supabase.from("badges")
            .delete().eq("id", value: badge.id).execute()
        await MainActor.run {
            self.receivedBadges.removeAll { $0.row.id == badge.id }
        }
    }

    // MARK: - Rides

    func fetchRides() async {
        guard let uid = currentUserId else { return }
        do {
            let rows: [RideRow] = try await supabase
                .from("rides")
                .select()
                .eq("user_id", value: uid)
                .order("started_at", ascending: false)
                .execute()
                .value
            await MainActor.run { self.rides = rows }
        } catch {
            print("fetchRides error: \(error)")
        }
    }

    func saveRide(title: String,
                  startedAt: Date, endedAt: Date,
                  distanceM: Double, durationS: Int,
                  visibility: RideVisibility,
                  points: [RidePoint]) async throws {
        guard let uid = currentUserId else {
            throw AppError.message("Sign in to save rides.")
        }

        struct InsertRide: Encodable {
            let user_id: UUID
            let title: String
            let started_at: String
            let ended_at: String
            let distance_m: Double
            let duration_s: Int
            let visibility: String
        }
        struct InsertedRide: Decodable {
            let id: UUID
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let inserted: InsertedRide = try await supabase.from("rides")
            .insert(InsertRide(
                user_id: uid,
                title: title.trimmingCharacters(in: .whitespaces),
                started_at: iso.string(from: startedAt),
                ended_at: iso.string(from: endedAt),
                distance_m: distanceM,
                duration_s: durationS,
                visibility: visibility.rawValue))
            .select("id")
            .single()
            .execute()
            .value

        if !points.isEmpty {
            struct InsertPoint: Encodable {
                let ride_id: UUID
                let seq: Int
                let lat: Double
                let lng: Double
                let speed_mps: Double?
                let ts: String
            }
            let rows = points.map { p in
                InsertPoint(ride_id: inserted.id,
                            seq: p.seq,
                            lat: p.lat, lng: p.lng,
                            speed_mps: p.speedMps,
                            ts: iso.string(from: p.ts))
            }
            // Batch in chunks to avoid enormous single payloads.
            let chunkSize = 500
            for start in stride(from: 0, to: rows.count, by: chunkSize) {
                let end = min(start + chunkSize, rows.count)
                try await supabase.from("ride_points")
                    .insert(Array(rows[start..<end]))
                    .execute()
            }
        }

        await fetchRides()
    }

    func fetchRidePoints(_ ride: RideRow) async -> [RidePoint] {
        do {
            let rows: [RidePoint] = try await supabase
                .from("ride_points")
                .select()
                .eq("ride_id", value: ride.id)
                .order("seq", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            print("fetchRidePoints error: \(error)")
            return []
        }
    }

    func updateRideVisibility(_ ride: RideRow, to visibility: RideVisibility) async throws {
        try await supabase.from("rides")
            .update(["visibility": visibility.rawValue])
            .eq("id", value: ride.id)
            .execute()
        await MainActor.run {
            if let idx = self.rides.firstIndex(where: { $0.id == ride.id }) {
                self.rides[idx].visibility = visibility.rawValue
            }
        }
    }

    func deleteRide(_ ride: RideRow) async throws {
        try await supabase.from("rides")
            .delete().eq("id", value: ride.id).execute()
        await MainActor.run { self.rides.removeAll { $0.id == ride.id } }
    }

    // MARK: - POI reports (user flags a bad point for moderator review)

    func reportPOI(_ poi: POI, reason: String, details: String) async throws {
        guard let userId = currentUserId else {
            throw AppError.message("Sign in to report a point.")
        }
        struct InsertReport: Encodable {
            let poi_id: String
            let reporter_id: UUID
            let reason: String
            let details: String
        }
        try await supabase.from("poi_reports").insert(
            InsertReport(poi_id: poi.id, reporter_id: userId,
                         reason: reason, details: details)
        ).execute()
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
        struct ApprovedRow: Decodable { let authorId: UUID?; enum CodingKeys: String, CodingKey { case authorId = "author_id" } }
        let updated: ApprovedRow = try await supabase
            .from("pois")
            .update(["status": "approved"])
            .eq("id", value: poi.id)
            .select("author_id")
            .single()
            .execute()
            .value
        await MainActor.run {
            if !self.pois.contains(where: { $0.id == poi.id }) {
                self.pois.append(poi)
            }
            showToast("✅ Point approved and published on the map.")
        }

        var body: [String: String] = [
            "poi_id":      poi.id,
            "poi_type":    poi.type,
            "title":       poi.title,
            "description": poi.description,
            "lat":         String(poi.lat),
            "lng":         String(poi.lng),
        ]
        if let authorId = updated.authorId {
            body["author_id"] = authorId.uuidString
        }
        try? await supabase.functions.invoke(
            "notify-poi-approved",
            options: .init(body: body)
        )
    }

    func rejectPOI(_ poi: POI) async throws {
        try await supabase
            .from("notifications")
            .delete()
            .eq("poi_id", value: poi.id)
            .execute()
        try await supabase
            .from("pois")
            .delete()
            .eq("id", value: poi.id)
            .execute()
        await MainActor.run {
            self.pois.removeAll { $0.id == poi.id }
            showToast("🗑️ Point rejected and deleted.")
        }
    }

    // MARK: - In-app Notifications

    func fetchNotifications() async {
        guard let userId = currentUserId else { return }
        do {
            let rows: [NotificationRow] = try await supabase
                .from("notifications")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            await MainActor.run { self.notifications = rows }
        } catch {
            print("fetchNotifications error: \(error)")
        }
    }

    func markNotificationRead(_ notification: NotificationRow) async {
        guard notification.readAt == nil else { return }
        let now = Date()
        await MainActor.run {
            if let idx = self.notifications.firstIndex(where: { $0.id == notification.id }) {
                self.notifications[idx].readAt = now
            }
        }
        do {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try await supabase
                .from("notifications")
                .update(["read_at": formatter.string(from: now)])
                .eq("id", value: notification.id)
                .execute()
        } catch {
            print("markNotificationRead error: \(error)")
        }
    }

    func markAllNotificationsRead() async {
        let unread = await MainActor.run { self.notifications.filter { !$0.isRead } }
        for n in unread {
            await markNotificationRead(n)
        }
    }

    private func startNotificationsListener() {
        notificationsTask?.cancel()
        guard currentUserId != nil else { return }
        notificationsTask = Task { [weak self] in
            let channel = supabase.channel("notifications-stream")
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "notifications")
            await channel.subscribe()
            for await change in changes {
                guard let self else { return }
                if case .insert = change {
                    await self.fetchNotifications()
                }
            }
        }
    }

    func openNotification(_ notification: NotificationRow) {
        Task { await markNotificationRead(notification) }
        guard let poiId = notification.poiId,
              let lat = notification.lat,
              let lng = notification.lng else { return }
        let poiType = notification.poiType ?? POIType.furto.rawValue
        let poi = POI(id: poiId, type: poiType,
                      lat: lat, lng: lng,
                      title: notification.title,
                      description: notification.body ?? "",
                      author: "", createdAt: notification.createdAt)
        notificationTargetPOI = poi
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
