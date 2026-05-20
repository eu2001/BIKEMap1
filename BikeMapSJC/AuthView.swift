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

                // MARK: Admin panel (mostrado logo abaixo do perfil pra admins)
                if appState.isAdmin {
                    Section {
                        Button {
                            showAdmin = true
                        } label: {
                            HStack {
                                Label("Painel do Administrador", systemImage: "shield.lefthalf.filled")
                                    .foregroundStyle(.purple)
                                Spacer()
                                if appState.pendingPOICount > 0 {
                                    Text("\(appState.pendingPOICount)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red))
                                }
                            }
                        }
                    } header: {
                        Text("Administração")
                    }
                }

                // MARK: Minhas Bikes
                Section {
                    if !hasBikes {
                        Text("Guarde as informações da sua bike. Em caso de perda ou desaparecimento, você terá todos os dados para ajudar na recuperação e alertar a comunidade.")
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

                // MARK: Notificações
                if !appState.notifications.isEmpty {
                    Section("Notificações") {
                        ForEach(appState.notifications.prefix(10)) { entry in
                            Button {
                                Task { await appState.openNotification(entry) }
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(notificationIcon(for: entry.type))
                                        .font(.title3)
                                        .frame(width: 36, height: 36)
                                        .background(Color.blue.opacity(0.12),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(entry.title)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(1)
                                                .foregroundStyle(.primary)
                                            if entry.read_at == nil {
                                                Circle().fill(Color.blue)
                                                    .frame(width: 6, height: 6)
                                            }
                                        }
                                        Text(entry.created_at.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if entry.poi_id != nil {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
                // Refresh the pending count so the red badge on
                // "Painel do Administrador" populates without waiting
                // for the next admin-screen open.
                await appState.refreshPendingCount()
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

    private func notificationIcon(for type: String) -> String {
        switch type {
        case "furto_alert":  return "🚨"
        case "poi_approved": return "✅"
        case "poi_rejected": return "🗑️"
        default:             return "🔔"
        }
    }
}
