//
//  MonthCalendarSheet.swift
//  RunClub
//
//  Created by Assistant on 8/15/25.
//

import SwiftUI

struct MonthCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthService
    @AppStorage("runsPerWeek") private var runsPerWeek: Int = 3
    @AppStorage("preferredDurationCategory") private var preferredDurationRaw: String = DurationCategory.medium.rawValue

    @Binding var selectedDate: Date
    let calendar: Calendar
    let isRunDay: (Date) -> Bool
    var isCompleted: (Date) -> Bool = { _ in false }

    @State private var showSettings: Bool = false
    private let schedule = ScheduleService()

    private var preferences: UserPreferences {
        let duration = DurationCategory(rawValue: preferredDurationRaw) ?? .medium
        return UserPreferences(runsPerWeek: runsPerWeek, preferredDuration: duration)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.082, green: 0.082, blue: 0.082), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    Text(monthTitle(for: selectedDate))
                        .font(RCFont.medium(32))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .overlay(Rectangle().fill(Color.white).frame(height: 1).padding(.horizontal, 20), alignment: .bottom)
                .padding(.bottom, 8)

                // Weekday headers
                HStack {
                    ForEach(weekdaySymbols(), id: \.self) { day in
                        Text(day)
                            .font(RCFont.medium(12))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)

                // Month grid
                let days = monthDays(for: selectedDate)
                VStack(spacing: 12) {
                    ForEach(0..<days.count/7, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let day = days[row*7 + col]
                                MonthDayCell(date: day,
                                             isSelected: day.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false,
                                             numberColor: colorForDay(day))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let d = day {
                                        let isPast = calendar.startOfDay(for: d) < calendar.startOfDay(for: Date())
                                        if isPast && !isCompleted(d) {
                                            // do nothing for past dates without a recorded run
                                        } else {
                                            selectedDate = d
                                            dismiss()
                                        }
                                    }
                                }
                                if col < 6 { Spacer(minLength: 0) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)

                Spacer()
            }
        }
        
    }

    private func monthDays(for ref: Date) -> [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: ref)
        guard let start = calendar.date(from: comps) else { return [] }
        let range = calendar.range(of: .day, in: .month, for: start) ?? 1..<31
        let firstWeekday = calendar.component(.weekday, from: start) // 1..7, Sunday=1 by default
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var items: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            items.append(calendar.date(byAdding: .day, value: day - 1, to: start))
        }
        // pad to multiple of 7
        while items.count % 7 != 0 { items.append(nil) }
        return items
    }

    private func weekdaySymbols() -> [String] {
        var symbols = calendar.veryShortWeekdaySymbols
        // rotate to match firstWeekday
        let shift = calendar.firstWeekday - 1
        if shift > 0 { symbols = Array(symbols[shift...]) + symbols[..<shift] }
        return symbols.map { $0.uppercased() }
    }

    private func monthTitle(for date: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "LLLL"; return df.string(from: date).uppercased()
    }

    private func colorForDay(_ date: Date?) -> Color {
        guard let d = date else { return Color.white.opacity(0.3) }
        // Completed runs: bright green #00FF00
        if isCompleted(d) { return Color(red: 0.0, green: 1.0, blue: 0.0) }
        // Past dates with no recorded run: 25% white
        let isPast = calendar.startOfDay(for: d) < calendar.startOfDay(for: Date())
        if isPast { return Color.white.opacity(0.25) }
        let rec = schedule.recommendationForToday(preferences: preferences, date: d)
        guard rec.isRunDay else { return Color.white.opacity(0.6) }
        switch rec.template {
        case .easyRun?, .longEasy?: return Color(red: 0.0, green: 0.81, blue: 1.0)
        case .strongSteady?, .pyramid?, .kicker?: return Color(red: 1.0, green: 0.70, blue: 0.0)
        case .shortWaves?, .longWaves?: return Color(red: 1.0, green: 0.20, blue: 0.40)
        default: return .white
        }
    }
}

private struct MonthDayCell: View {
    let date: Date?
    let isSelected: Bool
    let numberColor: Color
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? numberColor.opacity(0.2) : Color.clear)
                    .frame(width: 36, height: 36)
                Text(date.map { "\(calendar.component(.day, from: $0))" } ?? "")
                    .font(RCFont.medium(16))
                    .foregroundColor(numberColor)
            }
        }
        .frame(width: 44)
    }
}


