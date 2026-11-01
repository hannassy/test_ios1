// Features/Debug/Views/ReportDetailView.swift
// Полный контекст ошибки + кнопка копирования в чат.

import SwiftUI

struct ReportDetailView: View {
    let report: DiagnosticReport
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                // Метаданные
                Section("Общее") {
                    row("Время", report.date.formatted(date: .long, time: .complete))
                    row("Версия", "\(report.appVersion) (iOS \(report.iosVersion))")
                    row("Устройство", report.deviceModel)
                }

                // Ошибка
                Section("Ошибка") {
                    row("Функция", "\(report.feature).\(report.operation)")
                    row("Сообщение", report.userMessage)
                    row("Тип", report.technicalType)
                }

                // Контекст
                if !report.context.isEmpty {
                    Section("Контекст") {
                        ForEach(report.context.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            row(k, v)
                        }
                    }
                }

                // Цепочка шагов
                if !report.recentSteps.isEmpty {
                    Section("Последние шаги") {
                        ForEach(report.recentSteps, id: \.date) { step in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(step.feature).\(step.operation)")
                                    .font(.subheadline.monospaced())
                                Text(step.date.formatted(date: .omitted, time: .complete))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Фрагмент ответа сервера
                if let frag = report.serverResponseFragment, !frag.isEmpty {
                    Section("Ответ сервера (фрагмент)") {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(frag)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                // Кнопка копирования
                Section {
                    Button {
                        UIPasteboard.general.string = report.asPlainText()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Скопировано" : "Скопировать для отправки в чат")
                        }
                    }
                    .accessibilityLabel(copied ? "Скопировано в буфер обмена" : "Скопировать отчёт об ошибке")
                }
            }
            .navigationTitle("Отчёт об ошибке")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}
