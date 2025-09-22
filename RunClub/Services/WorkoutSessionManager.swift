//
//  WorkoutSessionManager.swift
//  RunClub
//
//  Manages HealthKit workout sessions and GPS route recording for running.
//

import Foundation
import HealthKit
import CoreLocation
import Combine

@MainActor
final class WorkoutSessionManager: NSObject, ObservableObject {
    // MARK: - Published state
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var totalDistanceMeters: Double = 0
    @Published private(set) var startDate: Date?
    @Published private(set) var endDate: Date?

    // MARK: - HealthKit
    private let healthStore = HKHealthStore()
    private var routeBuilder: HKWorkoutRouteBuilder?

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
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToShare: Set = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSeriesType.workoutRoute()
        ]

        let typesToRead: Set = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSeriesType.workoutRoute()
        ]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        isAuthorized = true
    }

    // MARK: - Session control
    func startRunningWorkout() async throws {
        if !isAuthorized { try await requestAuthorization() }

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }

        startDate = Date()
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
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

    func endWorkout() async {
        guard let started = startDate else { return }
        endDate = Date()
        locationManager.stopUpdatingLocation()

        // Create workout and save
        let duration = (endDate ?? Date()).timeIntervalSince(started)
        let distanceQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: totalDistanceMeters)
        let totalDistance = distanceQuantity
        let workout = HKWorkout(activityType: .running,
                                start: started,
                                end: endDate ?? Date(),
                                workoutEvents: nil,
                                totalEnergyBurned: nil,
                                totalDistance: totalDistance,
                                metadata: nil)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            healthStore.save(workout) { [weak self] _, _ in
                guard let self else { cont.resume(); return }
                // Save a distance sample as well
                let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
                let distanceSample = HKQuantitySample(type: distanceType, quantity: distanceQuantity, start: started, end: self.endDate ?? Date())
                self.healthStore.save(distanceSample) { _, _ in
                    cont.resume()
                }
            }
        }
        // Finish route with workout
        if let rb = routeBuilder {
            try? await rb.finishRoute(with: workout, metadata: nil)
        }
        routeBuilder = nil
        isRunning = false
        isPaused = false
    }
}

// MARK: - CLLocationManagerDelegate
extension WorkoutSessionManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) { }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.isRunning, !locations.isEmpty else { return }
            for location in locations {
                if let last = self.lastLocation { self.totalDistanceMeters += location.distance(from: last) }
                self.lastLocation = location
            }
            self.routeBuilder?.insertRouteData(locations) { _, _ in }
        }
    }
}



