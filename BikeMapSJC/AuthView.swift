import SwiftUI

// AuthView is shown when the user is already logged in (profile + logout)
struct AuthView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                        }
                        .padding(.vertical, 6)
                    }

                    Section("Estatísticas") {
                        LabeledContent("Pontos contribuídos",
                                       value: "\(profile.contributionCount)")
                    }
                }

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
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
