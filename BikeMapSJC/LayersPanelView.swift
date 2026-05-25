import SwiftUI

struct LayersPanelView: View {
    @ObservedObject var appState: AppState
    @State private var showFurtoAlert    = false
    @State private var showTypePicker    = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header
            HStack {
                Label("Mapa Cicloviário", systemImage: "bicycle")
                    .font(.headline).fontWeight(.bold)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        appState.showSidebar = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(Color(.systemGray5), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 8)

            Divider()

            // MARK: Layer list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    sectionLabel("Infraestrutura Ciclável", icon: "road.lanes")

                    ForEach(InfraType.allCases, id: \.rawValue) { type in
                        layerRow(key: type.rawValue, label: type.label,
                                 tint: type.color) {
                            legendLine(color: type.color, dashed: type.dashPattern != nil)
                                .frame(width: 28)
                        }
                    }

                    Divider().padding(.top, 4)
                    sectionLabel("Pontos de Interesse", icon: "mappin.and.ellipse")

                    ForEach(POIType.allCases, id: \.rawValue) { type in
                        layerRow(key: type.rawValue, label: type.label,
                                 tint: type.color) {
                            Text(type.emoji).frame(width: 28)
                        }
                    }

                    Divider().padding(.vertical, 8)

                    // Quick actions
                    actionRow("Mostrar tudo", icon: "eye.fill", tint: .primary) {
                        InfraType.allCases.forEach { appState.layerVisibility[$0.rawValue] = true }
                        POIType.allCases.forEach   { appState.layerVisibility[$0.rawValue] = true }
                    }
                    Divider().padding(.leading, 48)
                    actionRow("Limpar mapa", icon: "xmark.circle.fill", tint: .red) {
                        InfraType.allCases.forEach { appState.layerVisibility[$0.rawValue] = false }
                        POIType.allCases.forEach   { appState.layerVisibility[$0.rawValue] = false }
                    }
                    Divider().padding(.leading, 48)
                    actionRow("Ocultar tudo", icon: "eye.slash", tint: .secondary) {
                        InfraType.allCases.forEach { appState.layerVisibility[$0.rawValue] = false }
                        POIType.allCases.forEach   { appState.layerVisibility[$0.rawValue] = false }
                    }

                    if appState.currentUserName != nil {
                        Divider().padding(.vertical, 8)

                        // Adicionar ponto — light blue button
                        Button {
                            showTypePicker = true
                        } label: {
                            Label("Adicionar ponto", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                        .sheet(isPresented: $showTypePicker) {
                            POITypePickerSheet { type in
                                showTypePicker = false
                                appState.pendingPOIType = type
                                withAnimation(.spring(response: 0.35)) { appState.showSidebar = false }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    appState.mapPickingMode = .addPoint
                                }
                            }
                        }

                        // Alertar Comunidade — red background, white text
                        Button {
                            showFurtoAlert = true
                        } label: {
                            Label {
                                Text("Alertar Comunidade")
                            } icon: {
                                Text("🚨")
                            }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                        .alert("Alertar a comunidade?", isPresented: $showFurtoAlert) {
                            Button("Cancelar", role: .cancel) { }
                            Button("Confirmar", role: .destructive) {
                                appState.pendingPOIType = .furto
                                withAnimation(.spring(response: 0.35)) { appState.showSidebar = false }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    appState.mapPickingMode = .addPoint
                                }
                            }
                        } message: {
                            Text("Isso irá alertar os membros da comunidade BikeMap sobre uma bike desaparecida na região.")
                        }

                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 4)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 4, y: 0)
    }

    // MARK: - Helpers

    private func layerRow<Icon: View>(key: String, label: String, tint: Color,
                                      @ViewBuilder icon: () -> Icon) -> some View {
        let isOn = appState.layerVisibility[key] ?? false
        return Button {
            appState.layerVisibility[key] = !isOn
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? tint : Color(.systemGray3))
                icon()
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .opacity(isOn ? 1.0 : 0.45)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 50)
        }
    }

    private func sectionLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func actionRow(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
        }
    }

    private func legendLine(color: Color, dashed: Bool) -> some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to:    .init(x: 0,          y: size.height / 2))
            path.addLine(to: .init(x: size.width, y: size.height / 2))
            ctx.stroke(path, with: .color(color),
                       style: .init(lineWidth: 3, dash: dashed ? [6, 4] : []))
        }
        .frame(width: 28, height: 14)
    }
}

