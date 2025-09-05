//
//  ScheduleService.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import Foundation

struct DailyRecommendation {
    let isRunDay: Bool
    let template: RunTemplateType?
    let suggestedDurationCategory: DurationCategory?
}

final class ScheduleService {
    func recommendationForToday(preferences: UserPreferences, date: Date = Date(), calendar: Calendar = .current) -> DailyRecommendation {
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let weekday = calendar.component(.weekday, from: date) // 1=Sunday ... 7=Saturday
        let isWeekA = (weekOfYear % 2) == 0

        // Map runs per week to A/B weekly templates assigned to weekdays.
        // Sunday is the long run day.

        let plan: [Int: (RunTemplateType, DurationCategory)]

        switch preferences.runsPerWeek {
        case 2:
            if isWeekA {
                plan = [
                    3: (.strongSteady, .medium), // Tuesday
                    5: (.easyRun, .short)         // Thursday
                ]
            } else {
                plan = [
                    3: (.kicker, .medium),        // Tuesday
                    1: (.longEasy, .long)         // Sunday long
                ]
            }
        case 3:
            if isWeekA {
                plan = [
                    3: (.easyRun, .short),
                    5: (.strongSteady, .medium),
                    1: (.shortWaves, .medium) // Sunday
                ]
            } else {
                plan = [
                    3: (.easyRun, .short),
                    5: (.pyramid, .medium),
                    1: (.longEasy, .long) // Sunday long
                ]
            }
        case 4:
            if isWeekA {
                plan = [
                    2: (.easyRun, .short),  // Monday
                    4: (.strongSteady, .medium),
                    6: (.shortWaves, .medium),
                    1: (.longEasy, .long)
                ]
            } else {
                plan = [
                    2: (.easyRun, .short),
                    4: (.kicker, .medium),
                    6: (.longWaves, .medium),
                    1: (.strongSteady, .medium)
                ]
            }
        case 5:
            if isWeekA {
                plan = [
                    2: (.easyRun, .short),
                    3: (.strongSteady, .medium),
                    4: (.shortWaves, .medium),
                    6: (.easyRun, .short),
                    1: (.longEasy, .long)
                ]
            } else {
                plan = [
                    2: (.easyRun, .short),
                    3: (.pyramid, .medium),
                    4: (.strongSteady, .medium),
                    6: (.kicker, .medium),
                    1: (.easyRun, .short)
                ]
            }
        default:
            plan = [:]
        }

        if let (template, cat) = plan[weekday] {
            let durationCategory: DurationCategory
            if template == .longEasy {
                durationCategory = .long // 1.5× rule applied later in generation
            } else {
                // Default to user’s preferred category except Waves default to Medium
                if template == .shortWaves || template == .longWaves {
                    durationCategory = .medium
                } else {
                    durationCategory = preferences.preferredDuration
                }
            }
            return DailyRecommendation(isRunDay: true, template: template, suggestedDurationCategory: durationCategory)
        } else {
            return DailyRecommendation(isRunDay: false, template: nil, suggestedDurationCategory: nil)
        }
    }
}


