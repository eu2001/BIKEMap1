import SwiftUI

// MARK: - Send Badge Sheet
//
// Presented from FriendDetailView. Grid of 12 pre-defined badges.
// User picks one, optionally adds a short note, and taps Send.
// AppState.sendBadge writes to public.badges; the DB trigger
// then inserts a notification row for the recipient.

struct SendBadgeSheet: View {
    let friend: FriendRow
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Badge?
    @State private var note = ""
    @State private var sending = false
    @State private var errorMsg = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Recipient
                    HStack(spacing: 12) {
                        AvatarView(id: friend.avatar, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Para").font(.caption).foregroundStyle(.secondary)
                            Text(friend.username).font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    // Badge grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Badge.allCases) { b in
                            BadgeCard(badge: b, selected: selected == b) {
                                selected = b
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Note
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mensagem (opcional)")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.leading, 16)
                        TextField("Escreva algo pra acompanhar…", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                    }

                    if !errorMsg.isEmpty {
                        Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.caption)
                            .padding(.horizontal, 16)
                    }

                    // Send button
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if sending { ProgressView().tint(.white) }
                            Text(sending ? "Enviando…" : "Enviar distintivo")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selected == nil ? Color(.systemGray4) : Color.blue,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                    .disabled(selected == nil || sending)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Enviar distintivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func send() async {
        guard let b = selected else { return }
        sending = true; errorMsg = ""
        do {
            try await appState.sendBadge(
                to: friend.friendId,
                slug: b.rawValue,
                message: note.trimmingCharacters(in: .whitespaces)
            )
            appState.showToast("🎉 Distintivo enviado para \(friend.username)!")
            dismiss()
        } catch {
            errorMsg = "Não foi possível enviar. Tente novamente."
        }
        sending = false
    }
}


// MARK: - Badge card (grid cell)

private struct BadgeCard: View {
    let badge: Badge
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(badge.emoji).font(.system(size: 32))
                Text(badge.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(badge.subtitle).font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.blue.opacity(0.10) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.blue : Color(.systemGray4),
                            lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}


// MARK: - My Badges (received)
//
// Rendered from a Profile-tab NavigationLink. Shows badges other people
// have sent to the current user. Swipe to remove.

struct MyBadgesView: View {
    @ObservedObject var appState: AppState
    @State private var loading = true

    var body: some View {
        Group {
            if loading && appState.receivedBadges.isEmpty {
                ProgressView("Carregando distintivos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.receivedBadges.isEmpty {
                ContentUnavailableView {
                    Label("Nenhum distintivo ainda", systemImage: "rosette")
                } description: {
                    Text("Quando amigos te enviarem distintivos, eles aparecem aqui.")
                }
            } else {
                List {
                    ForEach(appState.receivedBadges) { received in
                        BadgeReceivedRow(received: received)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { try? await appState.removeReceivedBadge(received.row) }
                                } label: { Label("Remover", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Meus Distintivos")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loading = true
            await appState.fetchReceivedBadges()
            loading = false
        }
        .refreshable { await appState.fetchReceivedBadges() }
    }
}


// MARK: - Received badge row

private struct BadgeReceivedRow: View {
    let received: ReceivedBadge

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(received.badge?.emoji ?? "🎖️").font(.title)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(received.badge?.title ?? received.row.slug)
                    .font(.subheadline.weight(.semibold))
                Text(received.badge?.subtitle ?? "")
                    .font(.caption).foregroundStyle(.secondary)

                if !received.message.isEmpty {
                    Text("\u{201C}\(received.message)\u{201D}")
                        .font(.caption.italic())
                        .foregroundStyle(.primary.opacity(0.8))
                        .padding(.top, 2)
                }

                HStack(spacing: 6) {
                    if let sender = received.sender {
                        AvatarView(id: sender.avatar, size: 18)
                        Text("de \(sender.username)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let d = received.createdAt {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(d, style: .relative)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
