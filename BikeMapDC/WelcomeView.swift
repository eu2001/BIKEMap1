import SwiftUI

struct WelcomeView: View {
    @ObservedObject var appState: AppState
    @StateObject private var network = NetworkMonitor()

    @State private var tab: WelcomeTab = .login

    enum WelcomeTab { case login, register }

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.85, green: 0.93, blue: 1.0)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // MARK: Branding
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                        .padding(.top, 56)
                        .padding(.bottom, 16)

                    VStack(spacing: 4) {
                        Text("BikeMap DC")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("DC Bike Infrastructure Map")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 28)

                    // MARK: Auth card
                    VStack(spacing: 0) {
                        // Tab picker
                        Picker("", selection: $tab) {
                            Text("Sign in").tag(WelcomeTab.login)
                            Text("Create account").tag(WelcomeTab.register)
                        }
                        .pickerStyle(.segmented)
                        .padding(16)

                        Divider()

                        if tab == .login {
                            WelcomeLoginForm(appState: appState)
                        } else {
                            WelcomeRegisterForm(appState: appState)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 20)

                }
                .padding(.bottom, 40)
            }

            // Offline banner
            if !network.isConnected {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.subheadline.weight(.semibold))
                        Text("No internet connection")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange, ignoresSafeAreaEdges: [])
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: network.isConnected)
            }
        }
    }
}

// MARK: - Login Form

private struct WelcomeLoginForm: View {
    @ObservedObject var appState: AppState

    @State private var email    = ""
    @State private var password = ""
    @State private var error    = ""
    @State private var loading  = false
    @State private var showPw   = false

    var body: some View {
        VStack(spacing: 14) {
            fieldGroup {
                styledField("Email", text: $email, content: .emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Divider().padding(.leading, 16)
                HStack {
                    Group {
                        if showPw {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .padding(.leading, 16)
                    .frame(height: 44)
                    Button { showPw.toggle() } label: {
                        Image(systemName: showPw ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 16)
                    }
                }
            }

            if !error.isEmpty {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if loading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign in").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(email.isEmpty || password.isEmpty || loading)
            .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)
        }
        .padding(16)
    }

    private func submit() async {
        error = ""; loading = true
        defer { loading = false }
        do {
            try await appState.signIn(email: email.lowercased().trimmingCharacters(in: .whitespaces),
                                      password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Register Form

private struct WelcomeRegisterForm: View {
    @ObservedObject var appState: AppState

    @State private var username    = ""
    @State private var email       = ""
    @State private var password    = ""
    @State private var confirm     = ""
    @State private var avatar      = "capivara"
    @State private var error       = ""
    @State private var loading     = false
    @State private var showPw      = false
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 14) {
            fieldGroup {
                styledField("Username", text: $username, content: .username)
                Divider().padding(.leading, 16)
                styledField("Email", text: $email, content: .emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Divider().padding(.leading, 16)
                HStack {
                    Group {
                        if showPw {
                            TextField("Password (min. 4 characters)", text: $password)
                        } else {
                            SecureField("Password (min. 4 characters)", text: $password)
                        }
                    }
                    .textContentType(.newPassword)
                    .padding(.leading, 16)
                    .frame(height: 44)
                    Button { showPw.toggle() } label: {
                        Image(systemName: showPw ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 16)
                    }
                }
                Divider().padding(.leading, 16)
                HStack {
                    Group {
                        if showConfirm {
                            TextField("Confirm password", text: $confirm)
                        } else {
                            SecureField("Confirm password", text: $confirm)
                        }
                    }
                    .textContentType(.newPassword)
                    .padding(.leading, 16)
                    .frame(height: 44)
                    Button { showConfirm.toggle() } label: {
                        Image(systemName: showConfirm ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 16)
                    }
                }
            }

            // Avatar picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose your avatar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                HStack(spacing: 8) {
                    ForEach(avatarList, id: \.id) { av in
                        Button { avatar = av.id } label: {
                            VStack(spacing: 3) {
                                AvatarView(id: av.id, size: 48)
                                    .overlay(Circle().stroke(avatar == av.id ? Color.green : Color.clear, lineWidth: 3))
                                Text(av.name)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if av.id != avatarList.last?.id { Spacer() }
                    }
                }
            }

            if !error.isEmpty {
                Label(error, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if loading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Create account").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(username.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty || loading)
            .opacity(username.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty ? 0.5 : 1)
        }
        .padding(16)
    }

    private func submit() async {
        error = ""; loading = true
        defer { loading = false }
        let name = username.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3 else { error = "Name must be at least 3 characters."; return }
        guard email.contains("@") && email.contains(".") else { error = "Invalid email."; return }
        guard password.count >= 6 else { error = "Password must be at least 6 characters."; return }
        guard password == confirm else { error = "Passwords don't match."; return }
        do {
            try await appState.register(email: email.lowercased().trimmingCharacters(in: .whitespaces),
                                         password: password, username: name, avatar: avatar)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Helpers

private func fieldGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
        content()
    }
    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 0.5))
}

private func styledField(_ placeholder: String, text: Binding<String>, content: UITextContentType) -> some View {
    TextField(placeholder, text: text)
        .textContentType(content)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .padding(.horizontal, 16)
        .frame(height: 44)
}
