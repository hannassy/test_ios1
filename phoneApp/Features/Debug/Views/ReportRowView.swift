// Features/Debug/Views/ReportRowView.swift
// Строка отчёта в списке: время, функция, короткая суть.

import SwiftUI

struct ReportRowView: View {
    let report: DiagnosticReport

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(report.feature + "." + report.operation)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(report.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(report.userMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(report.feature).\(report.operation), \(report.userMessage), \(report.date.formatted(date: .abbreviated, time: .shortened))")
    }
}
