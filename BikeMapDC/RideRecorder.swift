import Foundation
import CoreLocation
import Combine

// MARK: - Ride Recorder
//
// Foreground-only GPS ride recorder. Uses CLLocationManager with a 10 m
// distanceFilter to keep the point count reasonable. State published so
// SwiftUI can render live stats. Background updates are OFF: the app must
// stay foregrounded for the recording to advance. A later commit can add
// the .always location entitlement + background updates.

final class RideRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase: Equatable { case idle, recording, paused }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var currentSpeedMps: Double = 0
    @Published private(set) var points: [RidePoint] = []
    @Published private(set) var lastCoordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var lastLoggedAt: Date?
    private var timerCancellable: AnyCancellable?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10                 // meters between updates
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: control

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        reset()
        startedAt = Date()
        phase = .recording
        manager.startUpdatingLocation()
        startTimer()
    }

    func pause() {
        guard phase == .recording else { return }
        pausedAt = Date()
        phase = .paused
        manager.stopUpdatingLocation()
        stopTimer()
    }

    func resume() {
        guard phase == .paused, let paused = pausedAt else { return }
        pausedTotal += Date().timeIntervalSince(paused)
        pausedAt = nil
        phase = .recording
        manager.startUpdatingLocation()
        startTimer()
    }

    /// Ends the ride. Returns the immutable summary — the caller
    /// (typically AppState) persists it and then calls `reset()`.
    func stop() -> (start: Date, end: Date, distanceM: Double, durationS: Int, points: [RidePoint])? {
        guard let start = startedAt else { return nil }
        if phase == .paused, let paused = pausedAt {
            pausedTotal += Date().timeIntervalSince(paused)
            pausedAt = nil
        }
        manager.stopUpdatingLocation()
        stopTimer()
        let end = Date()
        let elapsed = max(0, Int(end.timeIntervalSince(start) - pausedTotal))
        let snapshot = (start: start, end: end,
                        distanceM: distanceMeters, durationS: elapsed,
                        points: points)
        phase = .idle
        return snapshot
    }

    func reset() {
        startedAt = nil
        pausedAt = nil
        pausedTotal = 0
        lastLoggedAt = nil
        distanceMeters = 0
        elapsedSeconds = 0
        currentSpeedMps = 0
        points = []
        lastCoordinate = nil
        stopTimer()
    }

    // MARK: internals

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.recomputeElapsed() }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func recomputeElapsed() {
        guard let start = startedAt else { return }
        var elapsed = Date().timeIntervalSince(start) - pausedTotal
        if phase == .paused, let paused = pausedAt {
            elapsed -= Date().timeIntervalSince(paused)
        }
        elapsedSeconds = max(0, Int(elapsed))
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if phase == .recording && !(s == .authorizedWhenInUse || s == .authorizedAlways) {
            pause()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .recording else { return }
        for loc in locations {
            // Skip obviously bad fixes
            if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 30 { continue }
            let now = loc.timestamp
            if let last = points.last {
                let delta = RideMath.distance(last.coordinate, loc.coordinate)
                // Ignore stationary jitter (< 4 m) but only if we recently logged.
                if delta < 4, let ll = lastLoggedAt, now.timeIntervalSince(ll) < 3 { continue }
                distanceMeters += delta
            }
            let p = RidePoint(rideId: nil,
                              seq: points.count,
                              lat: loc.coordinate.latitude,
                              lng: loc.coordinate.longitude,
                              speedMps: loc.speed >= 0 ? loc.speed : nil,
                              ts: now)
            points.append(p)
            lastCoordinate = loc.coordinate
            lastLoggedAt = now
            currentSpeedMps = max(0, loc.speed)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal; keep the recording running.
        print("Ride recorder location error: \(error.localizedDescription)")
    }
}
