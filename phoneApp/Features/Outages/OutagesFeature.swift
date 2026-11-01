// Features/Outages/OutagesFeature.swift
//
// ═══════════════════════════════════════════════════════════
// ТОЧКА ВХОДА ФУНКЦИИ «СВІТЛО»
// ═══════════════════════════════════════════════════════════
//
// Этот класс — «корень» всего, что связано с графиком ДТЭК.
// Он:
//   1. Создаёт все зависимости (клиент, ViewModel).
//   2. Реализует AppFeature → попадает в реестр → появляется в меню.
//   3. По запросу меню отдаёт корневой экран функции.
//
// Всё остальное (экраны, клиент, модели) — внутри папки Outages/.
// Соседние функции (Audiobooks, Debug) не знают о существовании этого класса.

import SwiftUI

@MainActor
final class OutagesFeature: AppFeature {

    // Идентификатор должен совпадать с тем, что хранится в настройках навигации.
    let id: FeatureID = "outages"
    let title = "Світло"           // Текст в меню
    let symbolName = "bolt.fill"   // Иконка молнии (SF Symbols)

    // ViewModel создаётся один раз — при запуске приложения.
    // Одна ViewModel на всё время жизни функции.
    private let viewModel: OutageViewModel

    init(diagnosticLog: any DiagnosticRecording) {
        // Создаём реальный сетевой клиент.
        // В тестах OutagesFeature не используется — там создают ViewModel напрямую с заглушкой.
        self.viewModel = OutageViewModel(
            client: DtekAjaxClient(),
            addressStore: .shared,    // Общий синглтон хранилища адресов
            diagnostics: diagnosticLog
        )
    }

    func makeRootView() -> AnyView {
        // AnyView стирает конкретный тип — меню работает с любым View через этот тип.
        AnyView(OutagesRootView(viewModel: viewModel))
    }
}
