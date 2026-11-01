// Features/Outages/Views/DayScheduleView.swift
// Полоса 48 слотов (сегодня).

import SwiftUI

struct DayScheduleView: View {
    let snapshot: OutageSnapshot
    @State private var now = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let dayKey = OutageSnapshot.dayKey(for: now)
        let schedule = snapshot.factSchedule[dayKey] ?? snapshot.presetSchedule[dayKey] ?? [:]
        let currentSlot = OutageSnapshot.slotIndex(for: now)

        VStack(alignment: .leading, spacing: 8) {
            // Полоса слотов
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(0..<48, id: \.self) { i in
                        let status = schedule[String(i)] ?? .unknown
                        Rectangle()
                            .fill(slotColor(status))
                            .overlay {
                                if i == currentSlot {
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(.white, lineWidth: 2)
                                }
                            }
                    }
                }
                .frame(height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 36)

            // Метки времени
            HStack {
                Text("00:00").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("06:00").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("12:00").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("18:00").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("24:00").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onReceive(timer) { now = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("График на сегодня. Сейчас слот \(currentSlot + 1) из 48.")
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
