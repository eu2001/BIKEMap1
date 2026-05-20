import SwiftUI
import MapKit

struct AdminView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pendingPOIs: [POI] = []
    @State private var loading      = true
    @State private var processingId: String? = nil
    @State private var processingKind: ProcessKind? = nil
    @State private var editingPOI: POI? = nil
    @State private var rejectingPOI: POI? = nil

    private enum ProcessKind { case approve, reject }

    // Furto reports embed the photo as a "🖼️ <url>" line in the description.
    // These helpers extract / strip it so the admin can preview the photo.
    private static let photoRegex = try! NSRegularExpression(pattern: "🖼️\\s*(https?://\\S+)")
    fileprivate static func extractPhotoURL(_ text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = photoRegex.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return URL(string: String(text[r]))
    }
    fileprivate static func stripPhotoURL(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return photoRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Carregando pontos pendentes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pendingPOIs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("Nenhum ponto pendente")
                            .font(.headline)
                        Text("Todos os pontos foram revisados.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("\(pendingPOIs.count) ponto(s) aguardando revisão") {
                            ForEach(pendingPOIs) { poi in
                                poiCard(poi)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Painel Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await reload() }
            .sheet(item: $editingPOI) { poi in
                AdminEditPOISheet(appState: appState, poi: poi) { updated in
                    if let idx = pendingPOIs.firstIndex(where: { $0.id == updated.id }) {
                        pendingPOIs[idx] = updated
                    }
                }
            }
            .confirmationDialog(
                "Rejeitar este ponto?",
                isPresented: Binding(
                    get: { rejectingPOI != nil },
                    set: { if !$0 { rejectingPOI = nil } }
                ),
                titleVisibility: .visible,
                presenting: rejectingPOI
            ) { poi in
                Button("Rejeitar e excluir", role: .destructive) {
                    rejectingPOI = nil
                    Task { await reject(poi) }
                }
                Button("Cancelar", role: .cancel) { rejectingPOI = nil }
            } message: { _ in
                Text("Remove o ponto permanentemente. Não vai aparecer no mapa nem contar para o ranking.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - POI card

    private func poiCard(_ poi: POI) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack(spacing: 10) {
                Text(poi.poiType.emoji)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color(poi.poiType.uiColor).opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(poi.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(poi.poiType.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let date = poi.createdAt {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if processingId == poi.id {
                    ProgressView()
                }
            }

            // Mini map
            Map(position: .constant(.region(MKCoordinateRegion(
                center: poi.coordinate,
                span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )))) {
                Marker("", coordinate: poi.coordinate)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(true)

            // Photo (extracted from description) — admin needs to see it before approving
            if let photoURL = Self.extractPhotoURL(poi.description) {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    case .success(let img):
                        img.resizable().scaledToFit().cornerRadius(10)
                    case .failure:
                        Label("Foto indisponível", systemImage: "photo.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: 220)
            }

            // Description (with photo URL stripped so the link doesn't show twice)
            let descText = Self.stripPhotoURL(poi.description)
            if !descText.isEmpty {
                Text(descText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            // Author
            Text("Enviado por: \(poi.author)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Edit button (full width, above approve/reject)
            Button {
                editingPOI = poi
            } label: {
                Label("Editar antes de aprovar", systemImage: "pencil.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .disabled(processingId != nil)

            // Action buttons — `.borderless` so SwiftUI treats each Button as
            // its own tap target. Without this, a List row with multiple
            // Buttons routes any tap to the first one (Rejeitar).
            HStack(spacing: 10) {
                Button {
                    rejectingPOI = poi
                } label: {
                    if processingId == poi.id && processingKind == .reject {
                        ProgressView()
                            .tint(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Label("Rejeitar", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(processingId != nil)

                Button {
                    Task { await approve(poi) }
                } label: {
                    if processingId == poi.id && processingKind == .approve {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Label("Aprovar", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(processingId != nil)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func reload() async {
        loading = true
        pendingPOIs = await appState.fetchPendingPOIs()
        loading = false
    }

    private func approve(_ poi: POI) async {
        processingId = poi.id
        processingKind = .approve
        do {
            try await appState.approvePOI(poi)
            pendingPOIs.removeAll { $0.id == poi.id }
        } catch {
            appState.showToast("❌ Erro ao aprovar. Tente novamente.")
        }
        processingId = nil
        processingKind = nil
    }

    private func reject(_ poi: POI) async {
        processingId = poi.id
        processingKind = .reject
        do {
            try await appState.rejectPOI(poi)
            pendingPOIs.removeAll { $0.id == poi.id }
        } catch {
            appState.showToast("❌ Erro ao rejeitar. Tente novamente.")
        }
        processingId = nil
        processingKind = nil
    }
}

// MARK: - Edit Sheet
//
// Permite que o admin corrija título / descrição e arraste o mapa pra
// realocar o pino antes de aprovar.

private struct AdminEditPOISheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let poi: POI
    let onSaved: (POI) -> Void

    @State private var title:       String
    @State private var description: String
    @State private var coord:       CLLocationCoordinate2D
    @State private var mapPosition: MapCameraPosition
    @State private var saving       = false
    @State private var errorMsg     = ""

    init(appState: AppState, poi: POI, onSaved: @escaping (POI) -> Void) {
        self.appState = appState
        self.poi = poi
        self.onSaved = onSaved
        _title       = State(initialValue: poi.title)
        _description = State(initialValue: poi.description)
        _coord       = State(initialValue: poi.coordinate)
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(
            center: poi.coordinate,
            span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ZStack {
                        Map(position: $mapPosition)
                            .onMapCameraChange(frequency: .continuous) { context in
                                coord = context.region.center
                            }
                        VStack(spacing: 0) {
                            Image(systemName: "mappin")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.red)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            Spacer().frame(height: 30)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .padding(.horizontal, -4)

                    Text("Arraste o mapa para ajustar a posição do pino.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Localização")
                }

                Section("Tipo de ponto") {
                    Label {
                        Text(poi.poiType.label).foregroundStyle(.primary)
                    } icon: {
                        Text(poi.poiType.emoji)
                    }
                }

                Section("Informações") {
                    TextField("Título", text: $title)
                    TextField("Descrição", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Editar ponto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else {
                            Text("Salvar").fontWeight(.semibold)
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else {
            errorMsg = "Título não pode estar vazio."
            return
        }
        saving = true; errorMsg = ""
        do {
            try await appState.updatePOIContent(
                poi,
                title: trimmedTitle,
                description: description,
                lat: coord.latitude,
                lng: coord.longitude
            )
            let updated = POI(
                id: poi.id, type: poi.type,
                lat: coord.latitude, lng: coord.longitude,
                title: trimmedTitle, description: description,
                author: poi.author, createdAt: poi.createdAt
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMsg = "Não foi possível salvar. Tente novamente."
        }
        saving = false
    }
}
