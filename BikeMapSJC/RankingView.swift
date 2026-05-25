import SwiftUI

struct RankingView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var ranked: [(username: String, profile: ProfileRow)] = []
    @State private var loading = true
    @State private var moderating: ProfileRow? = nil
    @State private var confirmDelete: ProfileRow? = nil

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if ranked.isEmpty {
                    ContentUnavailableView(
                        "Nenhum contribuidor ainda",
                        systemImage: "person.3",
                        description: Text("Seja o primeiro a adicionar pontos ao mapa!")
                    )
                } else {
                    Section("Contribuidores do mapa") {
                        ForEach(Array(ranked.enumerated()), id: \.element.username) { index, entry in
                            rankRow(index: index, username: entry.username, profile: entry.profile)
                        }
                    }
                }

                if let myName = appState.currentUserName {
                    let myPOIs = appState.pois.filter { $0.author == myName }
                    if !myPOIs.isEmpty {
                        Section("Meus pontos adicionados") {
                            ForEach(myPOIs.suffix(10).reversed()) { poi in
                                HStack(spacing: 10) {
                                    Text(poi.poiType.emoji)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(poi.title).font(.subheadline).fontWeight(.medium)
                                        Text(poi.poiType.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        dismiss()
                                        appState.selectedPOI = poi
                                    } label: {
                                        Image(systemName: "location.circle").foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("🏆 Ranking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
            .task { await loadRanking() }
            .confirmationDialog(
                Text(moderating.map { "Moderar @\($0.username)" } ?? ""),
                isPresented: Binding(
                    get: { moderating != nil },
                    set: { if !$0 { moderating = nil } }
                ),
                titleVisibility: .visible,
                presenting: moderating
            ) { profile in
                Button(profile.isBlocked ? "Desbloquear" : "Bloquear (não pode adicionar pontos)") {
                    let target = profile
                    moderating = nil
                    Task { await moderate(target, action: target.isBlocked ? "unblock" : "block") }
                }
                Button("Excluir usuário do app", role: .destructive) {
                    let target = profile
                    moderating = nil
                    confirmDelete = target
                }
                Button("Cancelar", role: .cancel) { moderating = nil }
            }
            .alert(
                "Excluir definitivamente?",
                isPresented: Binding(
                    get: { confirmDelete != nil },
                    set: { if !$0 { confirmDelete = nil } }
                ),
                presenting: confirmDelete
            ) { profile in
                Button("Cancelar", role: .cancel) { confirmDelete = nil }
                Button("Excluir conta", role: .destructive) {
                    let target = profile
                    confirmDelete = nil
                    Task { await moderate(target, action: "delete") }
                }
            } message: { profile in
                Text("@\(profile.username) será removido permanentemente. Não poderá entrar novamente com esse e-mail.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func loadRanking() async {
        loading = true
        ranked = await appState.rankedUsers()
        loading = false
    }

    private func moderate(_ profile: ProfileRow, action: String) async {
        let ok = await appState.moderateUser(profile.id, action: action)
        await MainActor.run {
            if ok {
                switch action {
                case "block":   appState.showToast("🚫 @\(profile.username) bloqueado.")
                case "unblock": appState.showToast("✅ @\(profile.username) desbloqueado.")
                case "delete":  appState.showToast("🗑️ @\(profile.username) excluído.")
                default: break
                }
            } else {
                appState.showToast("❌ Não foi possível moderar @\(profile.username).")
            }
        }
        await loadRanking()
    }

    @ViewBuilder
    private func rankRow(index: Int, username: String, profile: ProfileRow) -> some View {
        let displayName = username == "admin" ? "Equipe BikeMap" : username
        let medal: String = index == 0 ? "🥇" : index == 1 ? "🥈" : index == 2 ? "🥉" : "\(index + 1)º"
        let isMe = username == appState.currentUserName

        HStack(spacing: 12) {
            Text(medal).font(.title3).frame(width: 36)

            AvatarView(id: profile.avatar, size: 40)
                .background(isMe ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayName).fontWeight(isMe ? .bold : .regular)
                    if profile.isPremium { Text("⭐").font(.caption) }
                    if profile.isAdmin   { Text("🛡️").font(.caption) }
                    if profile.isBlocked { Text("🚫").font(.caption) }
                    if isMe { Text("(você)").font(.caption).foregroundStyle(.secondary) }
                }
                Text("\(profile.contributionCount) pontos")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            if appState.isAdmin && !isMe && !profile.isAdmin {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(isMe ? Color.blue.opacity(0.05) : nil)
        .contentShape(Rectangle())
        .onTapGesture {
            guard appState.isAdmin, !isMe, !profile.isAdmin else { return }
            moderating = profile
        }
    }
}
