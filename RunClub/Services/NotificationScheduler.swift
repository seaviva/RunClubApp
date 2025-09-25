//
//  NotificationScheduler.swift
//  RunClub
//
//  Schedules local notifications for run phase cues (10s before and at change).
//

import Foundation
import UserNotifications

struct RunPhase {
    let name: String
    let effort: LocalGenerator.EffortTier
    let durationSeconds: Int
}

final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private init() {}

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func clearPending() async {
        let center = UNUserNotificationCenter.current()
        await center.removeAllPendingNotificationRequests()
    }

    func cancelRunCues() async {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<256).flatMap { ["run_pre_\($0)", "run_change_\($0)"] }
        await center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func scheduleCues(start: Date, phases: [RunPhase]) async {
        let center = UNUserNotificationCenter.current()
        var offset: TimeInterval = 0
        let sections = sectionLabels(for: phases)
        for (index, phase) in phases.enumerated() {
            // At-change notification (current phase starts now)
            let changeTime = start.addingTimeInterval(offset)
            let changeReq = makeRequest(id: "run_change_\(index)", title: "Now: \(phase.name)", body: sections[index], delivery: changeTime)
            await center.addSafe(changeReq)

            // 10s-before for next phase (skip before first, schedule for upcoming phase)
            if index + 1 < phases.count {
                let next = phases[index + 1]
                let preTime = start.addingTimeInterval(offset + TimeInterval(max(0, phase.durationSeconds - 10)))
                let preBody = "\(sectionLabels(for: phases)[index + 1]) in 0:10"
                let preReq = makeRequest(id: "run_pre_\(index+1)", title: "Next: \(next.name)", body: preBody, delivery: preTime)
                await center.addSafe(preReq)
            }
            offset += TimeInterval(phase.durationSeconds)
        }
    }

    // Reschedule cues starting from a given elapsed position. Used on resume after a pause.
    func rescheduleFromElapsed(start: Date, phases: [RunPhase], elapsedSeconds: Int) async {
        await clearPending()
        let center = UNUserNotificationCenter.current()
        var cumulative: TimeInterval = -TimeInterval(elapsedSeconds)
        let sections = sectionLabels(for: phases)
        for (index, phase) in phases.enumerated() {
            let startFromNow = cumulative
            // Schedule at-change only if phase start is in the future
            if startFromNow >= 0 {
                let changeTime = start.addingTimeInterval(startFromNow)
                let changeReq = makeRequest(id: "run_change_\(index)", title: "Now: \(phase.name)", body: sections[index], delivery: changeTime)
                await center.addSafe(changeReq)
            }
            // Pre notification for the NEXT phase if that pre time is in the future
            if index + 1 < phases.count {
                let preFromNow = startFromNow + TimeInterval(max(0, phase.durationSeconds - 10))
                if preFromNow >= 0 {
                    let next = phases[index + 1]
                    let preTime = start.addingTimeInterval(preFromNow)
                    let preBody = "\(sections[index + 1]) in 0:10"
                    let preReq = makeRequest(id: "run_pre_\(index+1)", title: "Next: \(next.name)", body: preBody, delivery: preTime)
                    await center.addSafe(preReq)
                }
            }
            cumulative += TimeInterval(phase.durationSeconds)
        }
    }

    // Heuristic section labeling based on effort tiers: warmup = leading EASY run, cooldown = trailing EASY run
    private func sectionLabels(for phases: [RunPhase]) -> [String] {
        var warmupCount = 0
        for p in phases { if p.effort == .easy { warmupCount += 1 } else { break } }
        var cooldownCount = 0
        for p in phases.reversed() { if p.effort == .easy { cooldownCount += 1 } else { break } }
        let total = phases.count
        return phases.enumerated().map { (idx, _) in
            if idx < warmupCount { return "Warmup" }
            if idx >= total - cooldownCount { return "Cooldown" }
            return "Main"
        }
    }

    private func effortLabel(for tier: LocalGenerator.EffortTier) -> String {
        switch tier {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        case .hard: return "Hard"
        case .max: return "Max"
        }
    }

    private func makeRequest(id: String, title: String, body: String, delivery: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.5, delivery.timeIntervalSinceNow), repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

private extension UNUserNotificationCenter {
    func addSafe(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.add(request) { _ in cont.resume() }
        }
    }
}


