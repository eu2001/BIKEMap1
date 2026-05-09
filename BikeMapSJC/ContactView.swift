import SwiftUI

struct ContactView: View {
    @Environment(\.dismiss) private var dismiss

    private let adminEmail = "ciclistas.sjc@gmail.com"

    var body: some View {
        NavigationStack {
            List {

                // MARK: About
                Section {
                    HStack(spacing: 14) {
                        Image("logo")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("BikeMap SJC")
                                .font(.headline)
                            Text("Mapa Cicloviário de São José dos Campos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // MARK: Contact
                Section("Fale com a administração") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("E-mail")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(adminEmail)
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                    } icon: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.blue)
                    }
                    .onTapGesture { openMail(subject: "Contato - BikeMap SJC", body: "") }

                    Text("Dúvidas, sugestões ou informações sobre o mapa cicloviário de SJC? Entre em contato com a equipe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Report error
                Section("Reportar problema") {
                    Button {
                        openMail(
                            subject: "Reportar Erro - BikeMap SJC",
                            body: "Descreva o problema encontrado no mapa:\n\n"
                        )
                    } label: {
                        Label("Reportar erro no mapa", systemImage: "exclamationmark.bubble.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))

                    Text("Encontrou um erro ou informação desatualizada no mapa? Use o botão acima para nos avisar por e-mail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Sobre o App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func openMail(subject: String, body: String) {
        let encoded = "mailto:\(adminEmail)?subject=\(subject)&body=\(body)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: encoded) {
            UIApplication.shared.open(url)
        }
    }
}
