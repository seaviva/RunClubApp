//
//  RunSessionManager.swift
//  RunClub
//
//  Manages HealthKit workout sessions and GPS route recording for running.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class RunSessionManager: NSObject, ObservableObject {
    // MARK: - Published state
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var totalDistanceMeters: Double = 0
    @Published private(set) var startDate: Date?
    @Published private(set) var endDate: Date?

    // MARK: - Location
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?

    // MARK: - Lifecycle
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Authorization
    func requestAuthorization() async throws {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        isAuthorized = (locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse)
    }

    // MARK: - Session control
    func startRunning() async throws {
        if !isAuthorized { try await requestAuthorization() }
        startDate = Date()
        isRunning = true
        isPaused = false
        totalDistanceMeters = 0
        lastLocation = nil
        locationManager.startUpdatingLocation()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        locationManager.stopUpdatingLocation()
        isPaused = true
    }

    func resume() {
        guard isRunning, isPaused else { return }
        locationManager.startUpdatingLocation()
        isPaused = false
    }

    func end() async {
        guard let started = startDate else { return }
        endDate = Date()
        locationManager.stopUpdatingLocation()
        isRunning = false
        isPaused = false
    }

    // Cancel the workout without saving any HealthKit workout or distance sample
    func cancel() {
        locationManager.stopUpdatingLocation()
        isRunning = false
        isPaused = false
        startDate = nil
        endDate = nil
        totalDistanceMeters = 0
    }
}

// MARK: - CLLocationManagerDelegate
extension RunSessionManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.isAuthorized = (status == .authorizedAlways || status == .authorizedWhenInUse)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.isRunning, !locations.isEmpty else { return }
            for location in locations {
                if let last = self.lastLocation { self.totalDistanceMeters += location.distance(from: last) }
                self.lastLocation = location
            }
            // Route recording not implemented in this simplified manager.
        }
    }
}



