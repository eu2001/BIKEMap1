import SwiftUI
import MapKit
import CoreLocation

// MARK: - Directions Sheet
//
// Lets the user pick a starting point (defaulting to their current location)
// and hands the resulting origin + destination to Apple Maps for turn-by-turn.

struct DirectionsSheet: View {
    let poi: POI
    @Environment(\.dismiss) private var dismiss

    private enum OriginKind: Hashable {
        case currentLocation
        case custom(String)          // human-readable address / place name
        case pointOnMap              // last-tapped map coordinate
    }

    @State private var originKind: OriginKind = .currentLocation
    @State private var customQuery: String = ""
    @State private var resolvedCustom: MKMapItem?
    @State private var searching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    Picker("Start", selection: $originKind) {
                        Text("Current Location").tag(OriginKind.currentLocation)
                        Text("An address or place").tag(OriginKind.custom(""))
                    }
                    .pickerStyle(.segmented)

                    if case .custom = originKind {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("e.g. 1600 Pennsylvania Ave", text: $customQuery)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .onSubmit { Task { await geocodeCustom() } }
                        }
                        if searching {
                            HStack { ProgressView(); Text("Looking up…").font(.caption) }
                        } else if let m = resolvedCustom {
                            Label(m.name ?? "Address selected", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        } else if let msg = errorMessage {
                            Label(msg, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                Section("To") {
                    HStack(spacing: 12) {
                        Text(poi.poiType.emoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(poi.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(String(format: "%.5f, %.5f", poi.lat, poi.lng))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        openInAppleMaps()
                    } label: {
                        Label("Get directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(readyToLaunch == false)
                    .listRowBackground(readyToLaunch ? Color.blue : Color(.systemGray4))
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("How to get there")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: derived

    private var readyToLaunch: Bool {
        switch originKind {
        case .currentLocation: return true
        case .custom:          return resolvedCustom != nil
        case .pointOnMap:      return false
        }
    }

    private func geocodeCustom() async {
        errorMessage = nil
        resolvedCustom = nil
        let q = customQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        req.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 38.9072, longitude: -77.0369),
            span: .init(latitudeDelta: 1.5, longitudeDelta: 1.5)
        )
        do {
            let resp = try await MKLocalSearch(request: req).start()
            if let first = resp.mapItems.first {
                resolvedCustom = first
            } else {
                errorMessage = "No place found for \"\(q)\""
            }
        } catch {
            errorMessage = "Search failed — check your connection."
        }
    }

    private func openInAppleMaps() {
        // On text-mode change, keep the last-entered query around
        if case .custom = originKind, resolvedCustom == nil {
            Task { await geocodeCustom() }
            return
        }

        let destPlacemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: poi.lat, longitude: poi.lng)
        )
        let dest = MKMapItem(placemark: destPlacemark)
        dest.name = poi.title

        var items: [MKMapItem]
        switch originKind {
        case .currentLocation:
            items = [MKMapItem.forCurrentLocation(), dest]
        case .custom:
            guard let src = resolvedCustom else { return }
            items = [src, dest]
        case .pointOnMap:
            items = [dest]
        }

        MKMapItem.openMaps(with: items, launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ])
        dismiss()
    }
}


// MARK: - Report Point Sheet
//
// Lets a signed-in user flag a POI for the moderator.
// Writes to public.poi_reports (RLS: authenticated INSERT of your own reports).

struct PointReportSheet: View {
    let poi: POI
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum Reason: String, CaseIterable, Identifiable {
        case doesNotExist       = "does_not_exist"
        case wrongLocation      = "wrong_location"
        case duplicate          = "duplicate"
        case spamInappropriate  = "spam_inappropriate"
        case other              = "other"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .doesNotExist:      return "Doesn't exist anymore"
            case .wrongLocation:     return "Wrong location"
            case .duplicate:         return "Duplicate of another point"
            case .spamInappropriate: return "Spam or inappropriate"
            case .other:             return "Something else"
            }
        }
    }

    @State private var reason: Reason = .doesNotExist
    @State private var details = ""
    @State private var submitting = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Text(poi.poiType.emoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(poi.poiType.label).font(.caption).foregroundStyle(.secondary)
                            Text(poi.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        }
                    }
                } header: {
                    Text("Reporting this point")
                }

                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(Reason.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextField("Optional details for the moderator",
                              text: $details, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Anything the moderator needs to know to act on this report.")
                        .font(.caption)
                }

                if !error.isEmpty {
                    Section {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if submitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Send report")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(submitting)
                    .listRowBackground(Color.red)
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("Report point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        error = ""
        submitting = true
        defer { submitting = false }

        do {
            try await appState.reportPOI(
                poi,
                reason: reason.rawValue,
                details: details.trimmingCharacters(in: .whitespaces)
            )
            appState.showToast("🚩 Report sent. A moderator will review it.")
            dismiss()
        } catch {
            self.error = "Couldn't send the report. Try again."
        }
    }
}
