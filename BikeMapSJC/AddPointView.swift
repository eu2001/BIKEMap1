import SwiftUI
import MapKit

struct AddPointView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: POIType = .paraciclo

    init(appState: AppState) {
        self.appState = appState
        _selectedType = State(initialValue: appState.pendingPOIType ?? .paraciclo)
    }
    @State private var title       = ""
    @State private var description = ""
    @State private var outOfBounds = false

    private var coordinate: CLLocationCoordinate2D? { appState.pendingAddCoordinate }

    // Type is always pre-selected before AddPointView opens
    private var generalTypes: [POIType] { POIType.allCases.filter { $0.canContribute && $0 != .furto && $0 != .acidente_ferido } }

    var body: some View {
        NavigationStack {
            Form {

                Section("Localização selecionada") {
                    if let coord = coordinate {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                            Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if outOfBounds {
                            Label(SJCBounds.outOfBoundsMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        // Mini map preview
                        Map(position: .constant(.region(MKCoordinateRegion(
                            center: coord,
                            span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        )))) {
                            Marker("", coordinate: coord)
                        }
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .padding(.horizontal, -4)
                    } else {
                        Label("Nenhuma localização selecionada", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
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
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || coordinate == nil || outOfBounds)
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
        .onChange(of: coordinate?.latitude) { _, _ in
            if let coord = coordinate {
                outOfBounds = !SJCBounds.contains(coord)
            }
        }
    }

    private func submit() {
        guard let coord = coordinate,
              !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard SJCBounds.contains(coord) else { outOfBounds = true; return }
        appState.addPOI(
            type: selectedType,
            coordinate: coord,
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces)
        )
        appState.pendingAddCoordinate = nil
        appState.pendingPOIType = nil
        dismiss()
    }
}
