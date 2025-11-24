//
//  RunOrchestrator.swift
//  RunClub
//
//  Drives run phases (WU/Core/CD) based on a list of phases with durations.
//  Publishes current/next info and coordinates notifications.
//

import Foundation
import Combine

@MainActor
final class RunOrchestrator: ObservableObject {
    struct PhaseState {
        let index: Int
        let name: String
        let effort: LocalGenerator.EffortTier
        let durationSeconds: Int
    }

    @Published private(set) var isActive: Bool = false
    @Published private(set) var current: PhaseState?
    @Published private(set) var next: PhaseState?
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var remainingSeconds: Int = 0

    private var phases: [PhaseState] = []
    private var startDate: Date?
    private var pauseStartDate: Date?
    private var totalPausedSeconds: Int = 0
    private var timer: Timer?
    var onCompleted: (() -> Void)?
    var onPhaseUpdate: ((PhaseState?, PhaseState?) -> Void)?

    func start(phases: [PhaseState]) async {
        guard !isActive else { return }
        self.phases = phases
        self.startDate = Date()
        self.pauseStartDate = nil
        self.totalPausedSeconds = 0
        self.isActive = true
        self.elapsedSeconds = 0
        self.remainingSeconds = phases.map { $0.durationSeconds }.reduce(0, +)
        updateNowNext(at: 0)
        await NotificationScheduler.shared.requestAuthorization()
        await NotificationScheduler.shared.clearPending()
        await NotificationScheduler.shared.scheduleCues(start: self.startDate!, phases: phases.map { RunPhase(name: $0.name, effort: $0.effort, durationSeconds: $0.durationSeconds) })
        startTimer()
    }

    func pause() {
        timer?.invalidate(); timer = nil
        pauseStartDate = Date()
        Task { await NotificationScheduler.shared.cancelRunCues() }
    }

    func resume() {
        guard isActive else { return }
        if let p = pauseStartDate, let s = startDate {
            totalPausedSeconds += Int(Date().timeIntervalSince(p))
            // Shift baseline so elapsed = now - (start + paused)
            startDate = s.addingTimeInterval(TimeInterval(totalPausedSeconds))
            pauseStartDate = nil
        }
        startTimer()
        Task {
            if let start = startDate {
                let runPhases = phases.map { RunPhase(name: $0.name, effort: $0.effort, durationSeconds: $0.durationSeconds) }
                await NotificationScheduler.shared.rescheduleFromElapsed(start: start, phases: runPhases, elapsedSeconds: elapsedSeconds)
            }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        isActive = false
        current = nil
        next = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        guard let start = startDate else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(start))
        let total = phases.map { $0.durationSeconds }.reduce(0, +)
        remainingSeconds = max(0, total - elapsedSeconds)

        // Determine current phase based on elapsed
        var acc = 0
        for (i, p) in phases.enumerated() {
            if elapsedSeconds < acc + p.durationSeconds {
                updateNowNext(at: i)
                return
            }
            acc += p.durationSeconds
        }
        // Completed
        stop()
        onCompleted?()
    }

    private func updateNowNext(at index: Int) {
        guard index < phases.count else { current = nil; next = nil; return }
        let p = phases[index]
        current = p
        if index + 1 < phases.count { next = phases[index + 1] } else { next = nil }
        onPhaseUpdate?(current, next)
    }
}


