// OutageWidget/SharedModels.swift
// Минимальный набор моделей, нужных виджету.
// В дальнейшем вынести в отдельный Swift Package (Shared), чтобы не дублировать.

import Foundation

// Копии из Features/Outages/Models/ — только то, что нужно виджету:
// SavedPlace, SlotStatus, DaySchedule, OutageSnapshot, OutageStatus, WidgetSnapshotStore.
// При вынесении в Shared Package этот файл удаляется.

enum DtekRegion: String, Codable, Sendable {
    case odesa, dnipro, kyiv, kyivObl, donetsk, zaporizhzhia
}

struct SavedPlace: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var label: String
    var region: DtekRegion
    var city: String
    var street: String
    var house: String
    var group: String
}

enum SlotStatus: String, Codable, Sendable {
    case on = "yes"
    case off = "no"
    case maybe = "maybe"
    case unknown

    var displayName: String {
        switch self {
        case .on:      return "Світло є"
        case .off:     return "Немає"
        case .maybe:   return "Возможно"
        case .unknown: return "Неизвестно"
        }
    }
}

typealias DaySchedule = [String: SlotStatus]

struct OutageSnapshot: Codable, Sendable {
    var place: SavedPlace
    var factSchedule: [String: DaySchedule]
    var presetSchedule: [String: DaySchedule]
    var fetchedAt: Date

    func currentStatus(at date: Date = .now) -> OutageStatus {
        let calendar = Calendar.current
        let dayKey = Self.dayKey(for: date)
        let slotIndex = Self.slotIndex(for: date)

        if let daySchedule = factSchedule[dayKey] {
            return status(from: daySchedule, slotIndex: slotIndex, source: .fact, date: date, calendar: calendar)
        }
        if let daySchedule = presetSchedule[dayKey] {
            return status(from: daySchedule, slotIndex: slotIndex, source: .preset, date: date, calendar: calendar)
        }
        return OutageStatus(currentSlot: .unknown, nextChange: nil, source: .noData)
    }

    private func status(from schedule: DaySchedule, slotIndex: Int, source: OutageStatus.StatusSource, date: Date, calendar: Calendar) -> OutageStatus {
        let current = schedule[String(slotIndex)] ?? .unknown
        var next: Date?
        for i in (slotIndex + 1)..<48 {
            if let s = schedule[String(i)], s != current {
                next = slotStartDate(index: i, base: date, calendar: calendar)
                break
            }
        }
        return OutageStatus(currentSlot: current, nextChange: next, source: source)
    }

    static func slotIndex(for date: Date) -> Int {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return h * 2 + (m >= 30 ? 1 : 0)
    }

    static func dayKey(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Kyiv")
        return fmt.string(from: date)
    }

    private func slotStartDate(index: Int, base: Date, calendar: Calendar) -> Date {
        let h = index / 2
        let m = (index % 2) * 30
        var comps = calendar.dateComponents([.year, .month, .day], from: base)
        comps.hour = h
        comps.minute = m
        comps.second = 0
        return calendar.date(from: comps) ?? base
    }
}

struct OutageStatus: Sendable {
    let currentSlot: SlotStatus
    let nextChange: Date?
    let source: StatusSource

    enum StatusSource: Sendable {
        case fact, preset, noData
    }
}

enum WidgetSnapshotStore {
    private static let filename = "outage_snapshot_v1.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.local.phoneapp")?
            .appending(path: filename)
    }

    static func load() -> OutageSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(OutageSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
