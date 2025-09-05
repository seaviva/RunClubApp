//
//  WeekStrip.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import SwiftUI

struct WeekStrip: View {
    @Binding var selectedDate: Date
    let preferences: UserPreferences
    let schedule: ScheduleService
    var isCompleted: (Date) -> Bool = { _ in false }
    private let calendar = Calendar.current

    var body: some View {
        let week = daysOfCurrentWeek(containing: selectedDate)
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.1) { index, day in
                let rec = schedule.recommendationForToday(preferences: preferences, date: day)
                let runColor = color(for: rec.template)
                DayCell(date: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        weekdayColor: Color.white.opacity(0.4),
                        numberColor: isCompleted(day) ? Color(red: 0.0, green: 1.0, blue: 0.4667) : (rec.isRunDay ? runColor : Color.white.opacity(0.4)),
                        selectedBackgroundFill: rec.isRunDay ? nil : Color.white.opacity(0.1))
                .onTapGesture { selectedDate = day }
                if index < week.count - 1 { Spacer() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private func daysOfCurrentWeek(containing date: Date) -> [Date] {
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private func color(for template: RunTemplateType?) -> Color {
        // Effort bins → consistent colors
        // EASY → #00CFFF, MEDIUM → #FFB300, HARD → #FF3366
        guard let template else { return .white }
        switch template {
        case .easyRun, .longEasy:
            return Color(red: 0.0, green: 0.81, blue: 1.0) // #00CFFF
        case .strongSteady, .pyramid, .kicker:
            return Color(red: 1.0, green: 0.70, blue: 0.0) // #FFB300
        case .shortWaves, .longWaves:
            return Color(red: 1.0, green: 0.20, blue: 0.40) // #FF3366
        }
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    var weekdayColor: Color = .secondary
    var numberColor: Color = .white
    var selectedBackgroundFill: Color? = nil
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 6) {
            Text(shortWeekday(date))
                .font(RCFont.medium(12))
                .foregroundColor(weekdayColor)
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? (selectedBackgroundFill ?? numberColor.opacity(0.2)) : Color.clear)
                    .frame(width: 36, height: 36)
                Text("\(calendar.component(.day, from: date))")
                    .font(RCFont.medium(15))
                    .foregroundColor(numberColor)
            }
        }
        .frame(width: 44)
    }

    private func shortWeekday(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEEE" // single-letter weekday, localized
        return fmt.string(from: date).uppercased()
    }
}


