import SwiftUI
import MapKit

struct AddPointView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: POIType = .paraciclo

    // Coordenada ao vivo — o usuário pode ajustar arrastando o mini-mapa.
    @State private var pinCoordinate: CLLocationCoordinate2D
    @State private var mapPosition:    MapCameraPosition
    @State private var title       = ""
    @State private var description = ""
    @State private var outOfBounds = false

    init(appState: AppState) {
        self.appState = appState
        // Fallback pro centro de São José dos Campos se nenhuma localização
        // tiver sido pré-selecionada (caso o usuário abra direto pelo menu).
        let initial = appState.pendingAddCoordinate
            ?? CLLocationCoordinate2D(latitude: -23.1794, longitude: -45.8869)
        _pinCoordinate = State(initialValue: initial)
        _mapPosition   = State(initialValue: .region(MKCoordinateRegion(
            center: initial,
            // Zoom mais próximo (200m × 200m) pra precisão na hora de
            // posicionar o ponto.
            span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )))
        _selectedType  = State(initialValue: appState.pendingPOIType ?? .paraciclo)
    }

    // Type is always pre-selected before AddPointView opens
    private var generalTypes: [POIType] {
        POIType.allCases.filter { $0.canContribute && $0 != .furto && $0 != .acidente_ferido }
    }

    var body: some View {
        NavigationStack {
            Form {

                Section {
                    // Coordenada ao vivo
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        Text(String(format: "%.5f, %.5f", pinCoordinate.latitude, pinCoordinate.longitude))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if outOfBounds {
                        Label(SJCBounds.outOfBoundsMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text("Arraste o novo ponto para a localização exata")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    // Mini-mapa interativo: arraste para posicionar o pino.
                    ZStack {
                        Map(position: $mapPosition)
                            .mapStyle(.standard(elevation: .flat))
                            .onMapCameraChange(frequency: .continuous) { context in
                                pinCoordinate = context.region.center
                                outOfBounds   = !SJCBounds.contains(pinCoordinate)
                            }

                        // Pino fixo no centro — a ponta marca o centro do mapa.
                        VStack(spacing: 0) {
                            Image(systemName: "mappin")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.red)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            // Espaçador abaixo pra ancorar a ponta do pino no centro.
                            Spacer().frame(height: 30)
                        }
                        .allowsHitTesting(false)

                        // Mira sutil pra deixar claro onde a ponta cai.
                        Circle()
                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                            .frame(width: 6, height: 6)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .padding(.horizontal, -4)

                } header: {
                    Text("Localização selecionada")
                }

                Section("Tipo de ponto") {
                    Label {
                        Text(selectedType.label).foregroundStyle(.primary)
                    } icon: {
                        Text(selectedType.emoji)
                    }
                }

                Section("Informações") {
                    TextField("Título *", text: $title)
                    TextField("Descrição (opcional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Text(selectedType.emoji)
                            Text("Adicionar \(selectedType.label)")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespaces).isEmpty || outOfBounds
                    )
                }
            }
            .navigationTitle("Novo Ponto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func submit() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard SJCBounds.contains(pinCoordinate) else { outOfBounds = true; return }
        appState.addPOI(
            type: selectedType,
            coordinate: pinCoordinate,
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces)
        )
        appState.pendingAddCoordinate = nil
        appState.pendingPOIType = nil
        dismiss()
    }
}
