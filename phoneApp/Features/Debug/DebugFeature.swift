// Features/Debug/DebugFeature.swift
//
// ═══════════════════════════════════════════════════════════
// ТОЧКА ВХОДА ФУНКЦИИ «DEBUG»
// ═══════════════════════════════════════════════════════════
//
// Debug — такой же пункт меню, как и остальные.
// Никакого специального кода для его подключения нет:
// одна строка в FeatureRegistry — и он появляется в меню.
//
// Эта функция читает DiagnosticLog.shared — тот же журнал,
// в который пишут OutagesFeature и AudiobooksFeature.
// Но сам Debug ничего в журнал не пишет — только читает.

import SwiftUI

@MainActor
final class DebugFeature: AppFeature {
    let id: FeatureID = "debug"
    let title = "Debug"
    let symbolName = "ladybug"  // Иконка жука — стандартная иконка отладки

    // Хотим DiagnosticLog (actor), а не только протокол DiagnosticRecording,
    // потому что DebugRootView вызывает loadReports() — метод, есть только у DiagnosticLog.
    private let log: DiagnosticLog

    init(diagnosticLog: any DiagnosticRecording) {
        // DiagnosticLog.shared — единственный экземпляр журнала в приложении.
        // diagnosticLog параметр нужен для совместимости с протоколом AppFeature,
        // но Debug всегда берёт именно shared-экземпляр, чтобы читать реальные отчёты.
        self.log = DiagnosticLog.shared
    }

    func makeRootView() -> AnyView {
        AnyView(DebugRootView(log: log))
    }
}
