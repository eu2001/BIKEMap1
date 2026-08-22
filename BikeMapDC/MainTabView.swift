import SwiftUI

// MARK: - Main Tab View
//
// Root view once the user is signed in. Four tabs: Map, Rides, Friends, Profile.
// Map keeps the existing full-screen map + layers sidebar unchanged; Rides and
// Friends are their own tabs (real functionality lands in follow-up commits).
// Profile replaces the pop-over auth sheet the top-right avatar used to open.

struct MainTabView: View {
    @ObservedObject var appState: AppState
    @State private var selection: Tab = .map

    enum Tab: Hashable {
        case map, rides, friends, profile
    }

    var body: some View {
        TabView(selection: $selection) {
            ContentView(appState: appState)
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(Tab.map)

            RidesTabView(appState: appState)
                .tabItem { Label("Rides", systemImage: "figure.outdoor.cycle") }
                .tag(Tab.rides)

            FriendsTabView(appState: appState)
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .tag(Tab.friends)

            ProfileTabView(appState: appState)
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
                .badge(appState.unreadNotificationCount == 0 ? 0 : appState.unreadNotificationCount)
        }
        .tint(.blue)
        // Push notifications open the Map tab and drop a POI sheet
        .onChange(of: appState.notificationTargetPOI) { _, poi in
            if poi != nil { selection = .map }
        }
    }
}


// MARK: - Profile Tab
//
// Hub screen the "Profile" tab presents. Header + navigation links to the
// existing sub-flows (bikes, ranking, admin, edit) plus sign-out.

struct ProfileTabView: View {
    @ObservedObject var appState: AppState
    @State private var showEditProfile = false
    @State private var showContact     = false
    @State private var confirmSignOut  = false

    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    HStack(spacing: 14) {
                        AvatarView(id: appState.currentUser?.avatar ?? "capivara", size: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.currentUserName ?? "Anonymous")
                                .font(.title3.weight(.semibold))
                            if appState.isAdmin {
                                Label("Admin", systemImage: "checkmark.seal.fill")
                                    .font(.caption).foregroundStyle(.blue)
                            }
                            if let cp = appState.currentProfile {
                                Text("\(cp.contributionCount) contributions")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { showEditProfile = true } label: {
                            Image(systemName: "pencil")
                                .padding(8)
                                .background(Color(.systemGray5), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    NavigationLink {
                        BikeListView(appState: appState)
                    } label: {
                        Label("My Bikes", systemImage: "bicycle")
                    }

                    NavigationLink {
                        NotificationsListView(appState: appState)
                    } label: {
                        HStack {
                            Label("Notifications", systemImage: "bell.fill")
                            Spacer()
                            if appState.unreadNotificationCount > 0 {
                                Text("\(appState.unreadNotificationCount)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }

                    NavigationLink {
                        RankingView(appState: appState)
                    } label: {
                        Label("Community Ranking", systemImage: "trophy.fill")
                    }
                }

                if appState.isAdmin {
                    Section("Moderation") {
                        NavigationLink {
                            AdminView(appState: appState)
                        } label: {
                            Label("Admin Panel", systemImage: "person.badge.shield.checkmark.fill")
                        }
                    }
                }

                Section("Help") {
                    Button {
                        showContact = true
                    } label: {
                        Label("Contact / Feedback", systemImage: "envelope.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(appState: appState)
            }
            .sheet(isPresented: $showContact) { ContactView() }
            .alert("Sign out?", isPresented: $confirmSignOut) {
                Button("Cancel", role: .cancel) { }
                Button("Sign out", role: .destructive) {
                    appState.logout()
                }
            }
            .task { await appState.fetchBikes() }
        }
    }
}


// MARK: - Notifications List
//
// Simple wrapper around appState.notifications; marks each read on tap.

struct NotificationsListView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.notifications.isEmpty {
                ContentUnavailableView(
                    "No notifications yet",
                    systemImage: "bell.slash",
                    description: Text("Alerts about approvals and stolen bikes will show up here.")
                )
            } else {
                List {
                    ForEach(appState.notifications) { n in
                        Button {
                            appState.openNotification(n)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: n.type == "furto_alert" ? "lock.open.fill" : "checkmark.seal.fill")
                                    .font(.title3)
                                    .foregroundStyle(n.type == "furto_alert" ? .red : .green)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(n.title).font(.subheadline.weight(.semibold))
                                    if let body = n.body {
                                        Text(body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                    }
                                    if let date = n.createdAt {
                                        Text(date, style: .relative)
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                if !n.isRead {
                                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appState.notifications.contains(where: { !$0.isRead }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") {
                        Task { await appState.markAllNotificationsRead() }
                    }
                    .font(.caption)
                }
            }
        }
        .task { await appState.fetchNotifications() }
    }
}


// MARK: - Rides tab (placeholder — real UI lands in the Rides commit)

struct RidesTabView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Rides coming soon", systemImage: "figure.outdoor.cycle")
            } description: {
                Text("Record a ride, save the GPS trail, and see it beside your past rides. Landing shortly.")
            }
            .navigationTitle("Rides")
        }
    }
}


// FriendsTabView lives in FriendsView.swift (real implementation).
// RidesTabView placeholder above will be replaced in the Rides commit.
