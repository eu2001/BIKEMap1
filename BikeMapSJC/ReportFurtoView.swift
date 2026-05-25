import SwiftUI
import PhotosUI
import MapKit

struct ReportFurtoView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var incidentDate    = Date()
    @State private var description     = ""
    @State private var contact         = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoUIImage: UIImage?
    @State private var loading          = false
    @State private var error            = ""
    @State private var showConfirmAlert = false
    @State private var selectedBike: BikeRow?
    @State private var outOfBounds      = false

    // Coordenada ao vivo do pino — arrastando o mini-mapa atualiza este valor.
    @State private var pinCoordinate: CLLocationCoordinate2D
    @State private var mapPosition:    MapCameraPosition

    init(appState: AppState) {
        self.appState = appState
        // Centro inicial: a coordenada que o usuário tocou no mapa principal,
        // ou o centro de SJC se nada foi pré-selecionado.
        let initial = appState.pendingAddCoordinate
            ?? CLLocationCoordinate2D(latitude: -23.1794, longitude: -45.8869)
        _pinCoordinate = State(initialValue: initial)
        _mapPosition   = State(initialValue: .region(MKCoordinateRegion(
            center: initial,
            span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )))
    }

    private var isRecent: Bool { Date().timeIntervalSince(incidentDate) < 2 * 24 * 3600 }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Location — mini-mapa arrastavel
                Section {
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

                    // Mini-mapa interativo: arraste para posicionar o pino com precisao.
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
                            Spacer().frame(height: 30)
                        }
                        .allowsHitTesting(false)

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
                    Text("Localização do incidente")
                }

                // MARK: Bike selector (if user has registered bikes)
                if !appState.bikes.isEmpty {
                    Section {
                        Picker("Selecionar bike", selection: $selectedBike) {
                            Text("Nenhuma selecionada").tag(Optional<BikeRow>.none)
                            ForEach(appState.bikes) { bike in
                                Text(bike.nickname + (bike.brand.isEmpty ? "" : " (\(bike.brand))"))
                                    .tag(Optional(bike))
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedBike) { _, bike in
                            guard let bike else { return }
                            // Auto-fill description with bike details
                            var parts: [String] = []
                            if !bike.brand.isEmpty  { parts.append("Marca: \(bike.brand)") }
                            if !bike.color.isEmpty  { parts.append("Cor: \(bike.color)") }
                            if !bike.aro.isEmpty    { parts.append("Aro: \(bike.aro)") }
                            if !bike.serialNumber.isEmpty { parts.append("Nº série: \(bike.serialNumber)") }
                            if !bike.details.isEmpty { parts.append(bike.details) }
                            description = parts.joined(separator: "\n")
                        }

                        if let bike = selectedBike {
                            HStack(spacing: 12) {
                                // Thumbnail
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
                                                Image(systemName: "bicycle")
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bike.nickname).font(.subheadline.weight(.semibold))
                                    HStack(spacing: 4) {
                                        if !bike.brand.isEmpty { Text(bike.brand).font(.caption).foregroundStyle(.secondary) }
                                        if !bike.color.isEmpty { Text("· \(bike.color)").font(.caption).foregroundStyle(.secondary) }
                                        if !bike.aro.isEmpty   { Text("· \(bike.aro)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    if !bike.serialNumber.isEmpty {
                                        Text("Nº série: \(bike.serialNumber)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Bike desaparecida")
                    } footer: {
                        Text("Selecione uma bike cadastrada para preencher automaticamente os detalhes.")
                            .font(.caption)
                    }
                }

                // MARK: Date & Time
                Section("Data e hora") {
                    DatePicker("Data e hora do ocorrido",
                               selection: $incidentDate,
                               in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }

                // MARK: Description
                Section("Descrição do incidente") {
                    TextField("Descreva o ocorrido e as características da bicicleta.",
                              text: $description, axis: .vertical)
                        .lineLimit(4...8)
                }

                // MARK: Photo
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoUIImage == nil ? "Adicionar foto da bicicleta" : "Trocar foto",
                              systemImage: "photo.badge.plus")
                    }
                    if let photoUIImage {
                        Image(uiImage: photoUIImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .listRowInsets(.init(top: 8, leading: 8, bottom: 8, trailing: 8))
                        Button(role: .destructive) {
                            self.photoUIImage = nil
                            self.photoData    = nil
                            self.selectedPhoto = nil
                        } label: {
                            Label("Remover foto", systemImage: "trash")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Foto da bicicleta (opcional)")
                }

                // MARK: Contact
                Section {
                    TextField("Telefone ou e-mail para contato", text: $contact)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Informações de contato")
                } footer: {
                    Text("Obrigatório — para que outros membros da comunidade possam te contatar.")
                        .font(.caption)
                }

                // MARK: Error
                if !error.isEmpty {
                    Section {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // MARK: Submit
                Section {
                    Button {
                        // Only offer community alert if incident was within the last 2 days
                        if isRecent {
                            showConfirmAlert = true
                        } else {
                            Task { await submit() }
                        }
                    } label: {
                        Group {
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Label {
                                    Text("Alertar Comunidade")
                                } icon: {
                                    Text("🚨")
                                }
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || contact.trimmingCharacters(in: .whitespaces).isEmpty || loading || outOfBounds)
                    .listRowBackground(Color.red)
                    .foregroundStyle(.white)
                }
                .alert("Alertar a comunidade?", isPresented: $showConfirmAlert) {
                    Button("Cancelar", role: .cancel) { }
                    Button("Sim, alertar", role: .destructive) {
                        Task { await submit() }
                    }
                } message: {
                    Text("Se o ocorrido foi há menos de 24h, todos os membros da comunidade BikeMap serão notificados sobre esta bike desaparecida na região.")
                }
            }
            .navigationTitle("Alertar Comunidade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: selectedPhoto) { _, item in
            Task {
                guard let item else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoData    = data
                    photoUIImage = UIImage(data: data)
                }
            }
        }
    }

    // MARK: - Submit

    private func submit() async {
        let coord = pinCoordinate
        guard SJCBounds.contains(coord) else { outOfBounds = true; return }
        let desc = description.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty else { return }
        let contactTrimmed = contact.trimmingCharacters(in: .whitespaces)
        guard !contactTrimmed.isEmpty else {
            error = "Informe um telefone ou e-mail para contato."
            return
        }

        error = ""; loading = true
        defer { loading = false }

        // Format date/time
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: incidentDate)

        // Upload photo if present
        var imageURL: String? = nil
        if let photoData {
            imageURL = await appState.uploadFurtoPhoto(photoData)
        }

        // Build description block
        var fullDesc = "📅 \(dateStr)\n📝 \(desc)\n📞 \(contactTrimmed)"
        if let url = imageURL {
            fullDesc += "\n🖼️ \(url)"
        }

        let poiTitle: String
        if let bike = selectedBike {
            poiTitle = "Bike desaparecida: \(bike.nickname)"
        } else {
            poiTitle = "Bike desaparecida"
        }

        appState.addPOI(
            type: .furto,
            coordinate: coord,
            title: poiTitle,
            description: fullDesc,
            incidentAt: incidentDate
        )

        appState.pendingAddCoordinate = nil
        appState.pendingPOIType = nil
        dismiss()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
