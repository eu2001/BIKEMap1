import SwiftUI
import MapKit

struct AdminView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pendingPOIs: [POI] = []
    @State private var loading      = true
    @State private var processingId: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading pending points...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pendingPOIs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("No pending points")
                            .font(.headline)
                        Text("All points have been reviewed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("\(pendingPOIs.count) point(s) awaiting review") {
                            ForEach(pendingPOIs) { poi in
                                poiCard(poi)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Admin Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
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

            // Description
            if !poi.description.isEmpty {
                Text(poi.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            // Author
            Text("Submitted by: \(poi.author)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    Task { await reject(poi) }
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.red)
                }
                .disabled(processingId != nil)

                Button {
                    Task { await approve(poi) }
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
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
        do {
            try await appState.approvePOI(poi)
            pendingPOIs.removeAll { $0.id == poi.id }
        } catch {
            appState.showToast("❌ Error approving. Try again.")
        }
        processingId = nil
    }

    private func reject(_ poi: POI) async {
        processingId = poi.id
        do {
            try await appState.rejectPOI(poi)
            pendingPOIs.removeAll { $0.id == poi.id }
        } catch {
            appState.showToast("❌ Error rejecting. Try again.")
        }
        processingId = nil
    }
}
