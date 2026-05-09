import SwiftUI
import MapKit
import CoreLocation
import Combine

struct ContentView: View {
    @ObservedObject var appState: AppState
    @StateObject private var locationManager = LocationManager()
    @StateObject private var network = NetworkMonitor()
    @State private var showContact = false

    var body: some View {
        ZStack(alignment: .top) {

            // MARK: Map (full screen)
            BikeMapView(appState: appState)
                .ignoresSafeArea()
                .task {
                    await appState.fetchInfraFeatures()
                }

            // MARK: Picking mode banner
            if appState.mapPickingMode != nil {
                pickingBanner
            }

            // MARK: Header
            header
                .padding(.top, topSafeArea)

            // MARK: Offline banner
            if !network.isConnected {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.subheadline.weight(.semibold))
                        Text("Sem conexão — o mapa pode estar desatualizado")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange, ignoresSafeAreaEdges: [])
                    Spacer()
                }
                .padding(.top, topSafeArea + 56)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: network.isConnected)
                .zIndex(2)
            }

            // MARK: Floating controls (right side)
            VStack {
                Spacer()
                floatingControls
                    .padding(.bottom, 30)
                    .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .ignoresSafeArea(edges: .bottom)

            // MARK: Toast
            if let msg = appState.toastMessage {
                VStack {
                    Spacer()
                    toastView(msg)
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
                .animation(.easeInOut, value: appState.toastMessage)
            }

            // MARK: Sidebar dim overlay
            if appState.showSidebar {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            appState.showSidebar = false
                        }
                    }
            }

            // MARK: Sidebar drawer (slides in from left)
            HStack(spacing: 0) {
                LayersPanelView(appState: appState)
                    .frame(width: 300)
                    .padding(.vertical, 60)
                    .contentShape(Rectangle())
                Spacer()
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .offset(x: appState.showSidebar ? 0 : -300)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.showSidebar)
            .allowsHitTesting(appState.showSidebar)

            // MARK: Left-edge tap zone (opens sidebar)
            if !appState.showSidebar {
                HStack {
                    Color.clear
                        .frame(width: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                appState.showSidebar = true
                            }
                        }
                    Spacer()
                }
                .ignoresSafeArea()
            }

            // MARK: Legend overlay
            if appState.showLegend {
                VStack {
                    Spacer()
                    LegendView(appState: appState)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
                .animation(.spring(response: 0.3), value: appState.showLegend)
            }
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $appState.showRanking)      { RankingView(appState: appState) }
        .sheet(isPresented: $appState.showAuth)         { AuthView(appState: appState) }
        .sheet(isPresented: $appState.showAddPoint) {
            if appState.pendingPOIType == .furto {
                ReportFurtoView(appState: appState)
            } else {
                AddPointView(appState: appState)
            }
        }
        .sheet(item: $appState.selectedPOI)             { poi in POIDetailView(poi: poi, appState: appState) }
        .sheet(isPresented: $showContact)               { ContactView() }
        .onReceive(locationManager.$authorizationStatus) { _ in }
        // Open POI detail when user taps a push notification
        .onChange(of: appState.notificationTargetPOI) { _, poi in
            guard let poi else { return }
            appState.shouldCenterOnUser = false
            appState.selectedPOI = poi
            appState.notificationTargetPOI = nil
        }
    }

    // MARK: - Header bar

    private var header: some View {
        HStack(spacing: 8) {
            Button { withAnimation { appState.showSidebar.toggle() } } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }

            Button { showContact = true } label: {
                Image("logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color(.systemGray3), lineWidth: 2)
                    )
            }

            Spacer()

            Button { appState.showRanking = true } label: {
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                            .padding(2)
                    )
            }

            if let name = appState.currentUserName {
                Button { appState.showAuth = true } label: {
                    AvatarView(id: appState.currentUser?.avatar ?? "capivara", size: 38)
                }
                .overlay(alignment: .topTrailing) {
                    if appState.currentUser?.isPremium == true {
                        Text("⭐").font(.system(size: 10)).offset(x: 4, y: -4)
                    }
                }
                let _ = name  // suppress warning
            } else {
                Button { appState.showAuth = true } label: {
                    Text("Entrar")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Floating controls

    private var floatingControls: some View {
        VStack(spacing: 10) {
            mapButton(icon: "location.fill") {
                locationManager.requestLocation()
                appState.shouldCenterOnUser = true
            }

            mapButton(icon: "plus.magnifyingglass") {
                appState.zoomDelta = 1
            }

            mapButton(icon: "minus.magnifyingglass") {
                appState.zoomDelta = -1
            }
        }
    }

    private func mapButton(icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
        }
    }

    // MARK: - Picking banner

    private var pickingBanner: some View {
        VStack {
            Spacer().frame(height: topSafeArea + 64)
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill").foregroundStyle(.white)
                Text(pickingModeLabel).foregroundStyle(.white).font(.subheadline).fontWeight(.medium)
                Spacer()
                Button("Cancelar") {
                    appState.mapPickingMode = nil
                }
                .foregroundStyle(.white.opacity(0.85))
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: appState.mapPickingMode != nil)
    }

    private var pickingModeLabel: String {
        switch appState.mapPickingMode {
        case .addPoint: return "Toque no mapa para adicionar um ponto"
        case .none:     return ""
        }
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
    }

    // MARK: - Safe area helper

    private var topSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }
}

// MARK: - Legend View

struct LegendView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Legenda").font(.headline)
                Spacer()
                Button { withAnimation { appState.showLegend = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            Text("Infraestrutura").font(.caption).foregroundStyle(.secondary).fontWeight(.semibold)
            ForEach(InfraType.allCases, id: \.rawValue) { type in
                HStack(spacing: 8) {
                    legendLine(color: type.color, dashed: type.dashPattern != nil)
                    Text(type.label).font(.caption)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Pontos de Interesse").font(.caption).foregroundStyle(.secondary).fontWeight(.semibold)
            let poiRows = POIType.allCases.chunked(into: 2)
            ForEach(0..<poiRows.count, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(poiRows[row], id: \.rawValue) { type in
                        HStack(spacing: 4) {
                            Text(type.emoji).font(.caption)
                            Text(type.label).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.15), radius: 8)
    }

    private func legendLine(color: Color, dashed: Bool) -> some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: .init(x: 0, y: size.height / 2))
            path.addLine(to: .init(x: size.width, y: size.height / 2))
            ctx.stroke(path, with: .color(color), style: .init(lineWidth: 3,
                dash: dashed ? [6, 4] : []))
        }
        .frame(width: 28, height: 14)
    }
}

// MARK: - POI Detail Sheet

struct POIDetailView: View {
    let poi: POI
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Text(poi.poiType.emoji).font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(poi.poiType.label).font(.caption).foregroundStyle(.secondary)
                            Text(poi.title).font(.headline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !poi.description.isEmpty {
                    Section("Descrição") {
                        Text(poi.description)
                    }
                }

                Section("Localização") {
                    HStack {
                        Label("Lat", systemImage: "location").font(.caption)
                        Spacer()
                        Text(String(format: "%.5f", poi.lat)).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Lng", systemImage: "location").font(.caption)
                        Spacer()
                        Text(String(format: "%.5f", poi.lng)).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Contribuição") {
                    Label("Por: \(poi.author == "admin" ? "Equipe BikeMap" : poi.author)", systemImage: "person.circle")
                }

            }
            .navigationTitle("Ponto no Mapa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Array chunk helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
