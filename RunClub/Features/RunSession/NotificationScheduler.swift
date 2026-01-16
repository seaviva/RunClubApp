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

final class NotificationScheduler: NSObject {
    static let shared = NotificationScheduler()
    
    /// Whether the user has granted notification permissions
    private(set) var isAuthorized: Bool = false
    
    /// Error message if authorization failed
    private(set) var authorizationError: String?
    
    private override init() {
        super.init()
        // Set ourselves as the delegate to handle foreground notifications
        UNUserNotificationCenter.current().delegate = self
    }

    /// Request notification authorization and return whether it was granted
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            isAuthorized = granted
            authorizationError = granted ? nil : "Notification permission denied"
            if !granted {
                print("[NOTIFICATIONS] Authorization denied by user")
            } else {
                print("[NOTIFICATIONS] Authorization granted")
            }
            return granted
        } catch {
            isAuthorized = false
            authorizationError = error.localizedDescription
            print("[NOTIFICATIONS] Authorization error: \(error)")
            return false
        }
    }
    
    /// Check current authorization status without prompting
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func clearPending() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    func cancelRunCues() async {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<256).flatMap { ["run_pre_\($0)", "run_change_\($0)"] }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func scheduleCues(start: Date, phases: [RunPhase]) async {
        // Verify we have authorization - request if not yet authorized
        if !isAuthorized {
            let granted = await requestAuthorization()
            if !granted {
                print("[NOTIFICATIONS] Cannot schedule cues - not authorized")
                return
            }
        }
        
        let center = UNUserNotificationCenter.current()
        var offset: TimeInterval = 0
        let sections = sectionLabels(for: phases)
        let now = Date()
        var scheduledCount = 0
        
        for (index, phase) in phases.enumerated() {
            // At-change notification (current phase starts now)
            let changeTime = start.addingTimeInterval(offset)
            // Only schedule if in the future
            if changeTime > now {
                if let changeReq = makeRequest(id: "run_change_\(index)", title: "Now: \(phase.name)", body: sections[index], deliveryDate: changeTime) {
                    await center.addSafe(changeReq)
                    scheduledCount += 1
                }
            }

            // 10s-before for next phase (skip before first, schedule for upcoming phase)
            if index + 1 < phases.count {
                let next = phases[index + 1]
                let preTime = start.addingTimeInterval(offset + TimeInterval(max(0, phase.durationSeconds - 10)))
                if preTime > now {
                    let preBody = "\(sectionLabels(for: phases)[index + 1]) in 0:10"
                    if let preReq = makeRequest(id: "run_pre_\(index+1)", title: "Next: \(next.name)", body: preBody, deliveryDate: preTime) {
                        await center.addSafe(preReq)
                        scheduledCount += 1
                    }
                }
            }
            offset += TimeInterval(phase.durationSeconds)
        }
        print("[NOTIFICATIONS] Scheduled \(scheduledCount) notifications for \(phases.count) phases")
    }

    // Reschedule cues starting from a given elapsed position. Used on resume after a pause.
    func rescheduleFromElapsed(start: Date, phases: [RunPhase], elapsedSeconds: Int) async {
        await cancelRunCues()
        
        guard isAuthorized else {
            print("[NOTIFICATIONS] Cannot reschedule - not authorized")
            return
        }
        
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let sections = sectionLabels(for: phases)
        var scheduledCount = 0
        
        // Calculate phase boundaries
        var phaseStartTimes: [TimeInterval] = []
        var cumulative: TimeInterval = 0
        for phase in phases {
            phaseStartTimes.append(cumulative)
            cumulative += TimeInterval(phase.durationSeconds)
        }
        
        for (index, phase) in phases.enumerated() {
            let phaseStartOffset = phaseStartTimes[index]
            let timeUntilPhaseStart = phaseStartOffset - TimeInterval(elapsedSeconds)
            
            // Schedule at-change only if phase start is in the future
            if timeUntilPhaseStart > 0.5 {
                let deliveryDate = now.addingTimeInterval(timeUntilPhaseStart)
                if let changeReq = makeRequest(id: "run_change_\(index)", title: "Now: \(phase.name)", body: sections[index], deliveryDate: deliveryDate) {
                    await center.addSafe(changeReq)
                    scheduledCount += 1
                }
            }
            
            // Pre notification for the NEXT phase if that pre time is in the future
            if index + 1 < phases.count {
                let preOffset = phaseStartOffset + TimeInterval(max(0, phase.durationSeconds - 10))
                let timeUntilPre = preOffset - TimeInterval(elapsedSeconds)
                if timeUntilPre > 0.5 {
                    let next = phases[index + 1]
                    let preBody = "\(sections[index + 1]) in 0:10"
                    let deliveryDate = now.addingTimeInterval(timeUntilPre)
                    if let preReq = makeRequest(id: "run_pre_\(index+1)", title: "Next: \(next.name)", body: preBody, deliveryDate: deliveryDate) {
                        await center.addSafe(preReq)
                        scheduledCount += 1
                    }
                }
            }
        }
        print("[NOTIFICATIONS] Rescheduled \(scheduledCount) notifications after resume (elapsed: \(elapsedSeconds)s)")
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

    /// Creates a notification request with proper time interval calculation
    /// Returns nil if the delivery date is not far enough in the future
    private func makeRequest(id: String, title: String, body: String, deliveryDate: Date) -> UNNotificationRequest? {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Use default sound for time-sensitive interruption
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        // Add a category for potential actions
        content.categoryIdentifier = "RUN_PHASE_CUE"
        
        // Calculate time interval at the moment of trigger creation (minimizes drift)
        let interval = deliveryDate.timeIntervalSinceNow
        
        // Must be at least 0.5 seconds in the future
        guard interval >= 0.5 else {
            print("[NOTIFICATIONS] Skipping notification '\(id)' - delivery time is in the past or too soon (\(interval)s)")
            return nil
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationScheduler: UNUserNotificationCenterDelegate {
    /// Handle notifications when app is in foreground - show them as banners
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        print("[NOTIFICATIONS] Presenting foreground notification: \(notification.request.identifier)")
        return [.banner, .sound, .badge]
    }
    
    /// Handle notification tap actions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        print("[NOTIFICATIONS] User interacted with notification: \(response.notification.request.identifier)")
        // Could add actions here like jumping to the run screen
    }
}

private extension UNUserNotificationCenter {
    func addSafe(_ request: UNNotificationRequest) async {
        do {
            try await self.add(request)
            print("[NOTIFICATIONS] Added: \(request.identifier)")
        } catch {
            print("[NOTIFICATIONS] Failed to add \(request.identifier): \(error)")
        }
    }
}


