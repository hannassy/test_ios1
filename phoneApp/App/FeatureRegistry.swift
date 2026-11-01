// App/FeatureRegistry.swift
//
// ═══════════════════════════════════════════════════════════
// РЕЕСТР — ЕДИНСТВЕННОЕ МЕСТО, ГДЕ ПЕРЕЧИСЛЕНЫ ВСЕ РАЗДЕЛЫ
// ═══════════════════════════════════════════════════════════
//
// Именно здесь определяется, какие пункты появятся в главном меню
// и в каком порядке.
//
// Чтобы добавить новый раздел:
//   1. Создать папку Features/MyFeature/
//   2. Создать класс, реализующий AppFeature
//   3. Добавить одну строку в массив ниже
//   Больше ничего в других файлах трогать не нужно.

import Foundation

// @MainActor — весь класс работает на главном потоке,
// потому что создаёт UI-компоненты (AppFeature.makeRootView).
@MainActor
final class FeatureRegistry {

    // Синглтон: один и тот же объект на всё время жизни приложения.
    // «static let» — переменная уровня типа, инициализируется один раз лениво (при первом обращении).
    static let shared = FeatureRegistry()

    // «any AppFeature» — элемент массива реализует протокол AppFeature,
    // но конкретный тип может быть любым (OutagesFeature, AudiobooksFeature и т.д.).
    // Ключевое слово any обязательно с Swift 5.7+ для экзистенциальных типов.
    private(set) var features: [any AppFeature]

    // private init() — снаружи создать нельзя, только через FeatureRegistry.shared.
    private init() {
        // DiagnosticLog — журнал ошибок. Передаём его каждой функции,
        // чтобы при сбое она могла записать отчёт.
        // Функции не знают друг о друге, но обе пишут в один общий журнал.
        let log = DiagnosticLog.shared

        // Порядок в массиве = порядок в меню.
        features = [
            OutagesFeature(diagnosticLog: log),    // «Світло» — первым
            AudiobooksFeature(diagnosticLog: log), // «Аудиокниги»
            DebugFeature(diagnosticLog: log),      // «Debug» — последним
        ]
    }
}
