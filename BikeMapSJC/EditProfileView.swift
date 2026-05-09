import SwiftUI

struct EditProfileView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var avatar        = ""
    @State private var selectedBikeId: String? = nil
    @State private var saving        = false
    @State private var errorMsg      = ""

    // Change password
    @State private var showChangePw   = false

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

                // MARK: Change password
                Section {
                    Button {
                        showChangePw = true
                    } label: {
                        Label("Alterar senha", systemImage: "lock.rotation")
                            .foregroundStyle(.blue)
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
        .sheet(isPresented: $showChangePw) {
            ChangePasswordSheet(appState: appState)
        }
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

// MARK: - Change Password Sheet

private struct ChangePasswordSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var newPassword     = ""
    @State private var confirmPassword = ""
    @State private var showNew         = false
    @State private var showConfirm     = false
    @State private var loading         = false
    @State private var success         = false
    @State private var errorMsg        = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if success {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("Senha alterada!")
                            .font(.title2.weight(.bold))
                        Text("Sua senha foi atualizada com sucesso.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text("Alterar senha")
                            .font(.title2.weight(.bold))
                        Text("Escolha uma senha com pelo menos 6 caracteres.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        // New password
                        HStack {
                            Group {
                                if showNew {
                                    TextField("Nova senha", text: $newPassword)
                                } else {
                                    SecureField("Nova senha", text: $newPassword)
                                }
                            }
                            .textContentType(.newPassword)
                            .padding(.leading, 16)
                            .frame(height: 48)
                            Button { showNew.toggle() } label: {
                                Image(systemName: showNew ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 16)
                            }
                        }

                        Divider().padding(.leading, 16)

                        // Confirm password
                        HStack {
                            Group {
                                if showConfirm {
                                    TextField("Confirmar nova senha", text: $confirmPassword)
                                } else {
                                    SecureField("Confirmar nova senha", text: $confirmPassword)
                                }
                            }
                            .textContentType(.newPassword)
                            .padding(.leading, 16)
                            .frame(height: 48)
                            Button { showConfirm.toggle() } label: {
                                Image(systemName: showConfirm ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 16)
                            }
                        }
                    }
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 0.5))
                    .padding(.horizontal, 24)

                    if !errorMsg.isEmpty {
                        Label(errorMsg, systemImage: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                    }

                    Button {
                        Task { await changePassword() }
                    } label: {
                        Group {
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Salvar nova senha").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                    .disabled(newPassword.isEmpty || confirmPassword.isEmpty || loading)
                    .opacity(newPassword.isEmpty || confirmPassword.isEmpty ? 0.5 : 1)
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .padding(.top, 32)
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

    private func changePassword() async {
        errorMsg = ""
        guard newPassword.count >= 6 else {
            errorMsg = "A senha deve ter ao menos 6 caracteres."; return
        }
        guard newPassword == confirmPassword else {
            errorMsg = "As senhas não coincidem."; return
        }
        loading = true
        defer { loading = false }
        do {
            try await appState.changePassword(newPassword: newPassword)
            success = true
        } catch {
            errorMsg = "Não foi possível alterar a senha. Tente novamente."
        }
    }
}
