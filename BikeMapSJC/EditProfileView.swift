import SwiftUI

struct EditProfileView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var avatar        = ""
    @State private var selectedBikeId: String? = nil
    @State private var saving        = false
    @State private var errorMsg      = ""

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Avatar picker
                Section("Avatar") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 12) {
                        ForEach(avatarList, id: \.id) { item in
                            Button {
                                avatar = item.id
                            } label: {
                                AvatarView(id: item.id, size: 52)
                                    .overlay(
                                        Circle()
                                            .stroke(avatar == item.id ? Color.blue : Color.clear, lineWidth: 3)
                                    )
                                    .scaleEffect(avatar == item.id ? 1.08 : 1.0)
                                    .animation(.spring(response: 0.25), value: avatar)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // MARK: Bike principal (only if user has bikes)
                if !appState.bikes.isEmpty {
                    Section {
                        // None option
                        Button {
                            selectedBikeId = nil
                        } label: {
                            HStack {
                                Image(systemName: "bicycle")
                                    .frame(width: 36, height: 36)
                                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(.secondary)
                                Text("Nenhuma").foregroundStyle(.primary)
                                Spacer()
                                if selectedBikeId == nil {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        ForEach(appState.bikes) { bike in
                            Button {
                                selectedBikeId = bike.id.uuidString
                            } label: {
                                HStack(spacing: 12) {
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
                                                    Image(systemName: "bicycle").foregroundStyle(.secondary)
                                                }
                                        }
                                    }
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bike.nickname)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            if !bike.brand.isEmpty { Text(bike.brand).font(.caption).foregroundStyle(.secondary) }
                                            if !bike.color.isEmpty { Text("· \(bike.color)").font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                    Spacer()
                                    if selectedBikeId == bike.id.uuidString {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Bike principal")
                    } footer: {
                        Text("Aparece em destaque no seu perfil.")
                    }
                }

                // MARK: Error
                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Editar Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Salvar").fontWeight(.semibold)
                        }
                    }
                    .disabled(saving)
                }
            }
            .onAppear {
                avatar         = appState.currentProfile?.avatar ?? "capivara"
                selectedBikeId = appState.selectedBikeId
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() async {
        saving = true; errorMsg = ""
        do {
            let currentUsername = appState.currentProfile?.username ?? ""
            try await appState.updateProfile(username: currentUsername, avatar: avatar)
            await MainActor.run { appState.selectedBikeId = selectedBikeId }
            dismiss()
        } catch {
            errorMsg = "Erro ao salvar perfil. Tente novamente."
        }
        saving = false
    }
}
