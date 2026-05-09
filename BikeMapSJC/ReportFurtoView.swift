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

    private var coordinate: CLLocationCoordinate2D? { appState.pendingAddCoordinate }
    private var isRecent: Bool { Date().timeIntervalSince(incidentDate) < 2 * 24 * 3600 }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Location
                Section("Localização do incidente") {
                    if let coord = coordinate {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                            Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Map(position: .constant(.region(MKCoordinateRegion(
                            center: coord,
                            span: .init(latitudeDelta: 0.004, longitudeDelta: 0.004)
                        )))) {
                            Marker("", coordinate: coord)
                        }
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .padding(.horizontal, -4)
                        if outOfBounds {
                            Label(SJCBounds.outOfBoundsMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Label("Nenhuma localização selecionada", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
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
                        Text("Bike furtada")
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
                    TextField("Descreva o que aconteceu, características da bicicleta, suspeitos, etc.",
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
                Section("Informações de contato") {
                    TextField("Telefone ou e-mail para contato (opcional)", text: $contact)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                                Label("Reportar Furto", systemImage: "lock.open.fill")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || coordinate == nil || loading || outOfBounds)
                    .listRowBackground(Color.red)
                    .foregroundStyle(.white)
                }
                .alert("Alertar a comunidade?", isPresented: $showConfirmAlert) {
                    Button("Cancelar", role: .cancel) { }
                    Button("Sim, alertar", role: .destructive) {
                        Task { await submit() }
                    }
                } message: {
                    Text("Ao confirmar, todos os membros da comunidade BikeMap serão notificados sobre este roubo de bicicleta na região.")
                }
            }
            .navigationTitle("Reportar Furto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: coordinate?.latitude) { _, _ in
            if let coord = coordinate {
                outOfBounds = !SJCBounds.contains(coord)
            }
        }
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
        guard let coord = coordinate else { return }
        guard SJCBounds.contains(coord) else { outOfBounds = true; return }
        let desc = description.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty else { return }

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
        var fullDesc = "📅 \(dateStr)\n📝 \(desc)"
        if let contact = contact.trimmingCharacters(in: .whitespaces).nonEmpty {
            fullDesc += "\n📞 \(contact)"
        }
        if let url = imageURL {
            fullDesc += "\n🖼️ \(url)"
        }

        let poiTitle: String
        if let bike = selectedBike {
            poiTitle = "Roubo: \(bike.nickname)"
        } else {
            poiTitle = "Roubo de Bicicleta"
        }

        appState.addPOI(
            type: .furto,
            coordinate: coord,
            title: poiTitle,
            description: fullDesc
        )

        appState.pendingAddCoordinate = nil
        appState.pendingPOIType = nil
        dismiss()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
