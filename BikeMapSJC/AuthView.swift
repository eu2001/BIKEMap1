import SwiftUI

// AuthView is shown when the user is already logged in (profile + logout)
struct AuthView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddBike     = false
    @State private var editingBike: BikeRow?
    @State private var deletingBike: BikeRow?
    @State private var loadingBikes    = false
    @State private var showEditProfile = false
    @State private var showAdmin       = false

    private var hasBikes: Bool { !appState.bikes.isEmpty }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Notifications
                if !appState.notifications.isEmpty {
                    Section {
                        ForEach(appState.notifications) { notification in
                            notificationRow(notification)
                        }
                    } header: {
                        HStack {
                            Text("Notificações")
                            if appState.unreadNotificationCount > 0 {
                                Text("(\(appState.unreadNotificationCount) novas)")
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                            if appState.unreadNotificationCount > 0 {
                                Button("Marcar como lidas") {
                                    Task { await appState.markAllNotificationsRead() }
                                }
                                .font(.caption)
                                .textCase(nil)
                            }
                        }
                    }
                }

                // MARK: Profile header
                if let profile = appState.currentProfile {
                    Section {
                        HStack(spacing: 14) {
                            AvatarView(id: profile.avatar, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.username).font(.headline)
                                if profile.isPremium {
                                    Label("Membro Premium", systemImage: "star.fill")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button {
                                showEditProfile = true
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)

                        // Selected bike card
                        if let bike = appState.selectedBike {
                            HStack(spacing: 12) {
                                Group {
                                    if let urlStr = bike.imageUrl, let url = URL(string: urlStr) {
                                        AsyncImage(url: url) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: { Color(.systemGray5) }
                                    } else {
                                        Color(.systemGray5)
                                            .overlay { Image(systemName: "bicycle").foregroundStyle(.secondary) }
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Label(bike.nickname, systemImage: "star.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 4) {
                                        if !bike.brand.isEmpty { Text(bike.brand).font(.caption).foregroundStyle(.secondary) }
                                        if !bike.color.isEmpty { Text("· \(bike.color)").font(.caption).foregroundStyle(.secondary) }
                                        if !bike.aro.isEmpty   { Text("· \(bike.aro)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // MARK: Admin panel (only for admins) — surfaced first so admins
                // can reach the review queue right after their name/avatar.
                if appState.isAdmin {
                    Section {
                        Button {
                            showAdmin = true
                        } label: {
                            Label("Painel do Administrador", systemImage: "shield.lefthalf.filled")
                                .foregroundStyle(.purple)
                        }
                    } header: {
                        Text("Administração")
                    }
                }

                // MARK: Minhas Bikes
                Section {
                    if !hasBikes {
                        Text("Guarde as informações da sua bike. Em caso de roubo, você terá todos os dados para ajudar na recuperação e alertar a comunidade.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 2)
                    }

                    ForEach(appState.bikes) { bike in
                        bikeRow(bike)
                    }

                    // Add / register button
                    Button {
                        showAddBike = true
                    } label: {
                        Label(
                            hasBikes ? "Adicionar novas bikes" : "Registrar sua magrela",
                            systemImage: hasBikes ? "plus.circle.fill" : "bicycle"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 12, bottom: 6, trailing: 12))
                } header: {
                    Text("Minhas bikes (\(appState.bikes.count))")
                }

                // MARK: Estatísticas + Pontos contribuídos (unified)
                Section("Contribuições (\(appState.userPOIs.count))") {
                    if let profile = appState.currentProfile {
                        LabeledContent("Total de pontos", value: "\(profile.contributionCount)")
                    }
                    ForEach(appState.userPOIs) { poi in
                        HStack(spacing: 12) {
                            Text(poi.poiType.emoji)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(Color(poi.poiType.uiColor).opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(poi.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(poi.poiType.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let date = poi.createdAt {
                                        Text("·")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }

                // MARK: Logout
                Section {
                    Button(role: .destructive) {
                        appState.logout()
                        dismiss()
                    } label: {
                        Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Meu Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
            .task {
                loadingBikes = true
                await appState.fetchBikes()
                await appState.fetchUserPOIs()
                await appState.fetchNotifications()
                loadingBikes = false
            }
            .sheet(isPresented: $showAddBike) {
                BikeFormView(appState: appState)
            }
            .sheet(item: $editingBike) { bike in
                BikeFormView(appState: appState, existing: bike)
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(appState: appState)
            }
            .sheet(isPresented: $showAdmin) {
                AdminView(appState: appState)
            }
            .alert("Remover bike?", isPresented: .init(
                get: { deletingBike != nil },
                set: { if !$0 { deletingBike = nil } }
            )) {
                Button("Cancelar", role: .cancel) { deletingBike = nil }
                Button("Remover", role: .destructive) {
                    if let bike = deletingBike {
                        Task { try? await appState.deleteBike(bike) }
                        deletingBike = nil
                    }
                }
            } message: {
                Text("Tem certeza que deseja remover \"\(deletingBike?.nickname ?? "")\"?")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Notification row

    private func notificationRow(_ notification: NotificationRow) -> some View {
        Button {
            appState.openNotification(notification)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notification.type == "furto_alert" ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(notification.type == "furto_alert" ? .red : .green)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(notification.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !notification.isRead {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                        }
                    }
                    if let body = notification.body, !body.isEmpty {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let date = notification.createdAt {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if notification.poiId != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bike row

    private func bikeRow(_ bike: BikeRow) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let urlStr = bike.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(.systemGray5)
                    }
                } else {
                    Color(.systemGray5)
                        .overlay {
                            Image(systemName: "bicycle")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(bike.nickname).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    if !bike.brand.isEmpty { Text(bike.brand).font(.caption).foregroundStyle(.secondary) }
                    if !bike.color.isEmpty { Text("· \(bike.color)").font(.caption).foregroundStyle(.secondary) }
                    if !bike.aro.isEmpty   { Text("· \(bike.aro)").font(.caption).foregroundStyle(.secondary) }
                }
                if !bike.serialNumber.isEmpty {
                    Text("Nº série: \(bike.serialNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !bike.details.isEmpty {
                    Text(bike.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Edit / delete menu
            Menu {
                Button { editingBike = bike } label: {
                    Label("Editar", systemImage: "pencil")
                }
                Button(role: .destructive) { deletingBike = bike } label: {
                    Label("Remover", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
