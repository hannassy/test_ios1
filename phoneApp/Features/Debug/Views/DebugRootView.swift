// Features/Debug/Views/DebugRootView.swift
// Список отчётов об ошибках. Читает журнал из DiagnosticLog.

import SwiftUI

struct DebugRootView: View {
    @State private var reports: [DiagnosticReport] = []
    @State private var selectedReport: DiagnosticReport?
    @State private var showClearConfirm = false
    private let log: DiagnosticLog

    init(log: DiagnosticLog) {
        self.log = log
    }

    var body: some View {
        NavigationStack {
            Group {
                if reports.isEmpty {
                    ContentUnavailableView(
                        "Ошибок нет",
                        systemImage: "checkmark.seal",
                        description: Text("Когда что-то пойдёт не так, отчёт появится здесь")
                    )
                } else {
                    reportList
                }
            }
            .navigationTitle("Debug")
            .toolbar { toolbarContent }
            .sheet(item: $selectedReport) { report in
                ReportDetailView(report: report)
            }
            .confirmationDialog("Очистить журнал?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { clearLog() }
                Button("Отмена", role: .cancel) {}
            }
            .task { await loadReports() }
        }
    }

    private var reportList: some View {
        List(reports) { report in
            Button {
                selectedReport = report
            } label: {
                ReportRowView(report: report)
            }
            .buttonStyle(.plain)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if !reports.isEmpty {
                Button("Очистить", role: .destructive) {
                    showClearConfirm = true
                }
                .foregroundStyle(.red)
                .accessibilityLabel("Очистить журнал ошибок")
            }
        }
    }

    private func loadReports() async {
        reports = await log.loadReports()
    }

    private func clearLog() {
        Task {
            try? await log.clearReports()
            await MainActor.run { reports = [] }
        }
    }
}
