//
//  OperatingHoursProvider.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import Foundation

struct OperatingHoursProvider {
    struct TimeRange {
        let startMinutes: Int
        let endMinutes: Int
        let startLabel: String
        let endLabel: String

        func contains(_ minute: Int) -> Bool { minute >= startMinutes && minute < endMinutes }
    }

    struct DisplayInfo {
        let isOpenNow: Bool
        let opensText: String?
        let closesText: String?
    }

    struct DaySchedule {
        let dayName: String
        let ranges: [TimeRange]
    }

    static let shared = OperatingHoursProvider()

    private let calendar: Calendar
    private let schedules: [String: [Int: [TimeRange]]]

    private init() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone.current
        calendar = cal
        schedules = OperatingHoursProvider.buildSchedules()
    }

    func displayInfo(for hallID: String, date: Date = Date()) -> DisplayInfo? {
        guard let scheduleByDay = schedules[hallID] else { return nil }
        let weekday = calendar.component(.weekday, from: date) // Sunday = 1 ... Saturday = 7
        let minuteOfDay = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        if let currentRange = scheduleByDay[weekday]?.first(where: { $0.contains(minuteOfDay) }) {
            return DisplayInfo(isOpenNow: true, opensText: currentRange.startLabel, closesText: currentRange.endLabel)
        }

        if let laterToday = scheduleByDay[weekday]?.first(where: { minuteOfDay < $0.startMinutes }) {
            return DisplayInfo(isOpenNow: false, opensText: laterToday.startLabel, closesText: nil)
        }

        for offset in 1...7 {
            let nextWeekday = ((weekday - 1 + offset) % 7) + 1
            if let nextRange = scheduleByDay[nextWeekday]?.first {
                return DisplayInfo(isOpenNow: false, opensText: nextRange.startLabel, closesText: nil)
            }
        }

        return nil
    }

    func weeklySchedule(for hallID: String) -> [DaySchedule]? {
        guard let scheduleByDay = schedules[hallID] else { return nil }
        return (1...7).compactMap { weekday in
            guard let ranges = scheduleByDay[weekday], !ranges.isEmpty else { return nil }
            let index = (weekday - 1 + calendar.firstWeekday - 1) % 7
            let dayName = calendar.weekdaySymbols[index]
            return DaySchedule(dayName: dayName, ranges: ranges)
        }
    }

    private static func minutes(_ hour: Int, _ minute: Int) -> Int { hour * 60 + minute }

    private static func range(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int, _ startLabel: String, _ endLabel: String) -> TimeRange {
        let endMinutesValue = (endHour == 24) ? minutes(24, 0) : minutes(endHour, endMinute)
        return TimeRange(startMinutes: minutes(startHour, startMinute), endMinutes: endMinutesValue, startLabel: startLabel, endLabel: endLabel)
    }

    private static func buildSchedules() -> [String: [Int: [TimeRange]]] {
        let northWeekend = [range(9, 0, 21, 0, "9am", "9pm")]
        let northWeekday = [
            range(7, 0, 24, 0, "7am", "12am"),
            range(0, 0, 2, 0, "12am", "2am")
        ]
        let northFriday = [range(7, 0, 22, 0, "7am", "10pm")]

        let westWeekend = [range(9, 0, 21, 0, "9am", "9pm")]
        let westWeekday = [range(7, 0, 23, 0, "7am", "11pm")]

        return [
            "north-ave": [
                1: northWeekend,
                2: northWeekday,
                3: northWeekday,
                4: northWeekday,
                5: northWeekday,
                6: northFriday,
                7: northWeekend
            ],
            "willage": [
                1: westWeekend,
                2: westWeekday,
                3: westWeekday,
                4: westWeekday,
                5: westWeekday,
                6: westWeekday,
                7: westWeekend
            ]
        ]
    }
}
