import SwiftUI
import MapKit
import CoreLocation

// MARK: - Rides Tab

struct RidesTabView: View {
    @ObservedObject var appState: AppState
    @State private var showRecorder = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.rides.isEmpty {
                    ContentUnavailableView {
                        Label("No rides yet", systemImage: "figure.outdoor.cycle")
                    } description: {
                        Text("Tap Record to start capturing a ride. Keep the app open — GPS runs in the foreground only for now.")
                    } actions: {
                        Button {
                            showRecorder = true
                        } label: {
                            Label("Record a ride", systemImage: "record.circle")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                    }
                } else {
                    List {
                        ForEach(appState.rides) { r in
                            NavigationLink {
                                RideDetailView(ride: r, appState: appState)
                            } label: {
                                RideListRow(ride: r)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { try? await appState.deleteRide(r) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Rides")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecorder = true
                    } label: {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Record ride")
                }
            }
            .sheet(isPresented: $showRecorder) {
                RideRecorderSheet(appState: appState)
            }
            .task { await appState.fetchRides() }
            .refreshable { await appState.fetchRides() }
        }
    }
}

// MARK: - Ride list row

private struct RideListRow: View {
    let ride: RideRow
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.outdoor.cycle")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(ride.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 10) {
                    Label(String(format: "%.2f km", ride.distanceKm), systemImage: "ruler")
                        .font(.caption).foregroundStyle(.secondary)
                    Label(ride.formattedDuration, systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: ride.visibilityEnum.systemImage)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Ride Recorder Sheet
//
// Live stats + start/pause/stop controls. On stop, prompts for a title
// and visibility, then persists the ride + points via AppState.

struct RideRecorderSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = RideRecorder()

    @State private var showSavePrompt = false
    @State private var pendingSummary: (start: Date, end: Date, distanceM: Double,
                                         durationS: Int, points: [RidePoint])?
    @State private var title = ""
    @State private var visibility: RideVisibility = .friends
    @State private var saving = false
    @State private var errorMsg = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Live map
                Map(position: .constant(.userLocation(fallback: .automatic))) {
                    UserAnnotation()
                    if recorder.points.count >= 2 {
                        MapPolyline(coordinates: recorder.points.map(\.coordinate))
                            .stroke(.blue, lineWidth: 4)
                    }
                }
                .mapStyle(.standard)
                .frame(maxHeight: .infinity)

                // Stats
                VStack(spacing: 16) {
                    HStack {
                        stat(String(format: "%.2f km", recorder.distanceMeters / 1000),
                             label: "Distance")
                        Divider().frame(height: 32)
                        stat(formatted(seconds: recorder.elapsedSeconds), label: "Time")
                        Divider().frame(height: 32)
                        stat(String(format: "%.1f km/h", recorder.currentSpeedMps * 3.6),
                             label: "Speed")
                    }
                    controls
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(.regularMaterial)
            }
            .navigationTitle("Recording ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if recorder.phase == .idle {
                            dismiss()
                        } else {
                            // Ask to discard first
                            recorder.reset()
                            dismiss()
                        }
                    } label: { Text(recorder.phase == .idle ? "Close" : "Discard").foregroundStyle(.red) }
                }
            }
            .sheet(isPresented: $showSavePrompt, onDismiss: { saving = false }) {
                savePrompt
            }
        }
    }

    // MARK: controls

    @ViewBuilder
    private var controls: some View {
        switch recorder.phase {
        case .idle:
            Button {
                recorder.start()
            } label: {
                Label("Start", systemImage: "record.circle")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
        case .recording:
            HStack(spacing: 12) {
                Button {
                    recorder.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.primary)
                }
                Button {
                    stopAndPrompt()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
        case .paused:
            HStack(spacing: 12) {
                Button {
                    recorder.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                Button {
                    stopAndPrompt()
                } label: {
                    Label("Finish", systemImage: "checkmark")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func stopAndPrompt() {
        pendingSummary = recorder.stop()
        if pendingSummary == nil {
            recorder.reset()
            dismiss()
            return
        }
        // Preseed title with the day
        title = "Ride on \(pendingSummary!.start.formatted(date: .abbreviated, time: .shortened))"
        showSavePrompt = true
    }

    // MARK: save prompt sheet

    private var savePrompt: some View {
        NavigationStack {
            Form {
                if let s = pendingSummary {
                    Section("Summary") {
                        LabeledContent("Distance", value: String(format: "%.2f km", s.distanceM / 1000))
                        LabeledContent("Time",     value: formatted(seconds: s.durationS))
                        LabeledContent("Points",   value: "\(s.points.count)")
                    }
                }
                Section("Title") {
                    TextField("Name your ride", text: $title)
                }
                Section("Visibility") {
                    Picker("Who can see this ride?", selection: $visibility) {
                        ForEach(RideVisibility.allCases) { v in
                            Label(v.label, systemImage: v.systemImage).tag(v)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if !errorMsg.isEmpty {
                    Section {
                        Label(errorMsg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if saving { ProgressView().tint(.white) }
                            Text("Save ride").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(saving)
                    .listRowBackground(Color.blue)
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("Save ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        pendingSummary = nil
                        recorder.reset()
                        showSavePrompt = false
                        dismiss()
                    } label: { Text("Discard") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        guard let s = pendingSummary else { return }
        saving = true; errorMsg = ""
        do {
            try await appState.saveRide(
                title: title,
                startedAt: s.start, endedAt: s.end,
                distanceM: s.distanceM, durationS: s.durationS,
                visibility: visibility,
                points: s.points
            )
            recorder.reset()
            pendingSummary = nil
            showSavePrompt = false
            dismiss()
        } catch {
            errorMsg = "Couldn't save. Try again."
        }
        saving = false
    }

    // MARK: helpers

    private func stat(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
                .contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatted(seconds s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}


// MARK: - Ride Detail
//
// Loads the ride's GPS trail on demand and renders it on a map, plus
// summary stats and a visibility picker.

struct RideDetailView: View {
    let ride: RideRow
    @ObservedObject var appState: AppState

    @State private var points: [RidePoint] = []
    @State private var loading = true
    @State private var visibility: RideVisibility
    @State private var confirmDelete = false

    init(ride: RideRow, appState: AppState) {
        self.ride = ride
        self._appState = ObservedObject(wrappedValue: appState)
        self._visibility = State(initialValue: ride.visibilityEnum)
    }

    var body: some View {
        List {
            Section {
                Map {
                    if points.count >= 2 {
                        MapPolyline(coordinates: points.map(\.coordinate))
                            .stroke(.blue, lineWidth: 4)
                    }
                    if let first = points.first {
                        Marker("Start", systemImage: "flag.checkered",
                               coordinate: first.coordinate).tint(.green)
                    }
                    if let last = points.last, points.count > 1 {
                        Marker("Finish", systemImage: "flag.fill",
                               coordinate: last.coordinate).tint(.red)
                    }
                }
                .frame(height: 260)
                .listRowInsets(.init())
                .overlay(alignment: .center) {
                    if loading { ProgressView().padding(8)
                        .background(.regularMaterial, in: Capsule()) }
                }
            }

            Section("Summary") {
                LabeledContent("Distance",  value: String(format: "%.2f km", ride.distanceKm))
                LabeledContent("Duration",  value: ride.formattedDuration)
                LabeledContent("Avg speed", value: String(format: "%.1f km/h", ride.averageSpeedKmh))
                LabeledContent("Started",   value: ride.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Ended",     value: ride.endedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Visibility") {
                Picker("Who can see this ride?", selection: $visibility) {
                    ForEach(RideVisibility.allCases) { v in
                        Label(v.label, systemImage: v.systemImage).tag(v)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: visibility) { _, new in
                    Task { try? await appState.updateRideVisibility(ride, to: new) }
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete ride", systemImage: "trash")
                }
            }
        }
        .navigationTitle(ride.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this ride?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { try? await appState.deleteRide(ride) }
            }
        } message: {
            Text("The GPS trail and stats will be permanently removed.")
        }
        .task {
            loading = true
            defer { loading = false }
            points = await appState.fetchRidePoints(ride)
        }
    }
}
