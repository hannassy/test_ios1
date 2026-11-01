// Features/Outages/Views/CurrentStatusView.swift
// Карточка текущего статуса света.

import SwiftUI

struct CurrentStatusView: View {
    let status: OutageStatus

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.currentSlot.displayName)
                    .font(.title2.bold())
                    .accessibilityLabel("Сейчас: \(status.currentSlot.displayName)")

                if let next = status.nextChange {
                    Text("До \(next.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("До следующего переключения в \(next.formatted(date: .omitted, time: .shortened))")
                }

                if status.source == .preset {
                    Label("Прогноз", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch status.currentSlot {
        case .on:      return "bolt.fill"
        case .off:     return "bolt.slash.fill"
        case .maybe:   return "bolt.badge.clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch status.currentSlot {
        case .on:      return .yellow
        case .off:     return .gray
        case .maybe:   return .orange
        case .unknown: return .secondary
        }
    }
}

#Preview {
    List {
        CurrentStatusView(status: OutageStatus(
            currentSlot: .on,
            nextChange: Date().addingTimeInterval(3600),
            source: .fact
        ))
        CurrentStatusView(status: OutageStatus(
            currentSlot: .off,
            nextChange: Date().addingTimeInterval(1800),
            source: .preset
        ))
    }
}
