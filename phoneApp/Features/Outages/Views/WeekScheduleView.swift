// Features/Outages/Views/WeekScheduleView.swift
// Прогнозный недельный график из preset.

import SwiftUI

struct WeekScheduleView: View {
    let snapshot: OutageSnapshot

    private var weekDays: [(key: String, date: Date)] {
        let cal = Calendar.current
        return (0..<7).compactMap { offset -> (String, Date)? in
            guard let date = cal.date(byAdding: .day, value: offset, to: .now) else { return nil }
            let key = OutageSnapshot.dayKey(for: date)
            return (key, date)
        }
    }

    var body: some View {
        ForEach(weekDays, id: \.key) { (key, date) in
            let schedule = snapshot.presetSchedule[key] ?? [:]
            VStack(alignment: .leading, spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(0..<48, id: \.self) { i in
                            let status = schedule[String(i)] ?? .unknown
                            Rectangle().fill(slotColor(status))
                        }
                    }
                    .frame(height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 18)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Прогноз на \(date.formatted(.dateTime.weekday(.wide)))")
        }
    }

    private func slotColor(_ status: SlotStatus) -> Color {
        switch status {
        case .on:      return .yellow.opacity(0.85)
        case .off:     return Color(.systemGray4)
        case .maybe:   return .orange.opacity(0.7)
        case .unknown: return Color(.systemGray6)
        }
    }
}
