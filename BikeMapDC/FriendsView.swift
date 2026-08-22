import SwiftUI

// MARK: - Friends Tab
//
// The tab shows two lists: accepted friends and open requests
// (incoming + outgoing). "+" opens AddFriendView, which lets you
// search other users by username and send them a request.

struct FriendsTabView: View {
    @ObservedObject var appState: AppState
    @State private var showAddFriend = false
    @State private var tab: Which = .friends

    enum Which: String, CaseIterable { case friends = "Friends", requests = "Requests" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Which.allCases, id: \.self) { w in
                        if w == .requests {
                            let open = appState.incomingRequests.count + appState.outgoingRequests.count
                            if open > 0 {
                                Text("\(w.rawValue) (\(open))").tag(w)
                            } else {
                                Text(w.rawValue).tag(w)
                            }
                        } else {
                            Text(w.rawValue).tag(w)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Group {
                    switch tab {
                    case .friends:  friendsList
                    case .requests: requestsList
                    }
                }
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddFriend = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView(appState: appState)
            }
            .task { await appState.refreshFriendState() }
            .refreshable { await appState.refreshFriendState() }
        }
    }

    // MARK: friends list

    @ViewBuilder
    private var friendsList: some View {
        if appState.friends.isEmpty {
            ContentUnavailableView {
                Label("No friends yet", systemImage: "person.2.slash")
            } description: {
                Text("Tap the person-with-plus icon in the top right to search for someone by username and send them a request.")
            }
        } else {
            List {
                ForEach(appState.friends) { f in
                    NavigationLink {
                        FriendDetailView(friend: f, appState: appState)
                    } label: {
                        friendRow(f)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { try? await appState.removeFriend(f) }
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func friendRow(_ f: FriendRow) -> some View {
        HStack(spacing: 12) {
            AvatarView(id: f.avatar, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(f.username).font(.subheadline.weight(.semibold))
                    if f.isPremium { Text("⭐").font(.caption) }
                }
                Text("\(f.contributionCount) contributions")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: requests list

    @ViewBuilder
    private var requestsList: some View {
        if appState.incomingRequests.isEmpty && appState.outgoingRequests.isEmpty {
            ContentUnavailableView {
                Label("No pending requests", systemImage: "tray")
            } description: {
                Text("Incoming and outgoing friend requests will show up here.")
            }
        } else {
            List {
                if !appState.incomingRequests.isEmpty {
                    Section("Incoming") {
                        ForEach(appState.incomingRequests, id: \.0.id) { pair in
                            IncomingRequestRow(request: pair.0, profile: pair.1, appState: appState)
                        }
                    }
                }
                if !appState.outgoingRequests.isEmpty {
                    Section("Sent") {
                        ForEach(appState.outgoingRequests, id: \.0.id) { pair in
                            OutgoingRequestRow(request: pair.0, profile: pair.1, appState: appState)
                        }
                    }
                }
            }
        }
    }
}


// MARK: - Incoming request row

private struct IncomingRequestRow: View {
    let request: FriendRequestRow
    let profile: DirectoryProfile
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(id: profile.avatar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.username).font(.subheadline.weight(.semibold))
                if let n = profile.contributionCount {
                    Text("\(n) contributions")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    Task { try? await appState.respondToFriendRequest(request, accept: false) }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    Task { try? await appState.respondToFriendRequest(request, accept: true) }
                } label: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.green, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Outgoing request row

private struct OutgoingRequestRow: View {
    let request: FriendRequestRow
    let profile: DirectoryProfile
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(id: profile.avatar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.username).font(.subheadline.weight(.semibold))
                Text("Waiting for reply").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { try? await appState.cancelFriendRequest(request) }
            } label: {
                Text("Cancel")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(.systemGray5), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Add friend view (username search + send request)

struct AddFriendView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [DirectoryProfile] = []
    @State private var searching = false
    @State private var errorMsg = ""
    @State private var sentTo = Set<UUID>()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search by username", text: $query)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { Task { await search() } }
                    }
                } footer: {
                    Text("Ask your friend for the username they picked when signing up.")
                        .font(.caption)
                }

                if searching {
                    HStack { ProgressView(); Text("Searching…").font(.subheadline) }
                } else if !errorMsg.isEmpty {
                    Label(errorMsg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                } else if results.isEmpty && !query.isEmpty {
                    Text("No matches for \"\(query)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { p in
                            HStack(spacing: 12) {
                                AvatarView(id: p.avatar, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.username).font(.subheadline.weight(.semibold))
                                    if let n = p.contributionCount {
                                        Text("\(n) contributions")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if sentTo.contains(p.id) {
                                    Label("Sent", systemImage: "checkmark")
                                        .font(.caption).foregroundStyle(.green)
                                } else if p.id == appState.currentUserId {
                                    Text("You").font(.caption).foregroundStyle(.tertiary)
                                } else {
                                    Button {
                                        Task {
                                            do {
                                                try await appState.sendFriendRequest(to: p.id)
                                                sentTo.insert(p.id)
                                            } catch {
                                                errorMsg = "Couldn't send the request."
                                            }
                                        }
                                    } label: {
                                        Text("Add")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Color.blue, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Add a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: query) { _, _ in
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await search()
                }
            }
        }
    }

    private func search() async {
        errorMsg = ""
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        searching = true
        defer { searching = false }
        do {
            results = try await appState.searchProfiles(byUsername: q)
        } catch {
            errorMsg = "Search failed. Try again."
            results = []
        }
    }
}


// MARK: - Friend detail
//
// Placeholder detail view — shows their profile + contribution count.
// Deeper features (see their contributions on the map, message them)
// land in follow-up commits.

struct FriendDetailView: View {
    let friend: FriendRow
    @ObservedObject var appState: AppState

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AvatarView(id: friend.avatar, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(friend.username).font(.title3.weight(.semibold))
                            if friend.isPremium { Text("⭐") }
                        }
                        Text("\(friend.contributionCount) contributions")
                            .font(.caption).foregroundStyle(.secondary)
                        if let since = friend.since {
                            Text("Friends since \(since.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                Button(role: .destructive) {
                    Task { try? await appState.removeFriend(friend) }
                } label: {
                    Label("Remove friend", systemImage: "person.crop.circle.badge.minus")
                }
            }
        }
        .navigationTitle(friend.username)
        .navigationBarTitleDisplayMode(.inline)
    }
}
