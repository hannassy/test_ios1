// App/RootMenuView.swift
//
// ═══════════════════════════════════════════════════════════
// ГЛАВНОЕ МЕНЮ ПРИЛОЖЕНИЯ
// ═══════════════════════════════════════════════════════════
//
// Этот файл не знает о конкретных функциях.
// Он получает список AppFeature и отображает его как меню.
// Добавление нового раздела не требует изменений здесь.
//
// КАК УСТРОЕН ИНТЕРФЕЙС В SWIFTUI
// ───────────────────────────────────────────────────────────
// В SwiftUI интерфейс — это функция от состояния:
//   экран = f(данные)
// При изменении данных SwiftUI сам перерисовывает нужные части.
// Мы не «двигаем» кнопки вручную — мы описываем, как должен
// выглядеть экран при данных значениях переменных.

import SwiftUI

struct RootMenuView: View {

    // @State — переменная, при изменении которой SwiftUI перерисует экран.
    // selectedID хранит ID выбранного пункта меню.
    // Когда пользователь нажимает пункт — selectedID меняется — экран обновляется.
    @State private var selectedID: FeatureID?

    // Список функций: просто массив, без знания конкретных типов.
    private let features: [any AppFeature]

    init(features: [any AppFeature]) {
        self.features = features
    }

    var body: some View {
        // NavigationSplitView — двухколоночный layout:
        //   на iPad: левая колонка (меню) + правая (содержимое)
        //   на iPhone: одна колонка, переход push-навигацией
        NavigationSplitView {
            // ─── ЛЕВАЯ КОЛОНКА: СПИСОК ПУНКТОВ ─────────────────
            List(features, id: \.id, selection: $selectedID) { feature in
                // Label — стандартный элемент: иконка + текст.
                // systemImage берёт иконку из SF Symbols.
                Label(feature.title, systemImage: feature.symbolName)
                    // accessibilityLabel — текст для VoiceOver (незрячие пользователи).
                    // Без этого VoiceOver прочитает иконку как "изображение".
                    .accessibilityLabel(feature.title)
            }
            .navigationTitle("Своё")   // Заголовок в верхней строке

        } detail: {
            // ─── ПРАВАЯ КОЛОНКА / ДЕТАЛЬНЫЙ ЭКРАН ─────────────
            if let id = selectedID,
               let feature = features.first(where: { $0.id == id }) {
                // Просим функцию создать свой корневой экран.
                feature.makeRootView()
                    // .id(id) — SwiftUI сбрасывает состояние экрана при смене функции.
                    // Без этого, например, прокрутка одного экрана могла бы
                    // «переехать» на другой при переключении.
                    .id(id)
            } else {
                // Нет выбранного пункта — показываем подсказку.
                // ContentUnavailableView — стандартный «пустой» экран Apple.
                ContentUnavailableView(
                    "Выбери раздел",
                    systemImage: "sidebar.left",
                    description: Text("Выбери пункт из меню слева")
                )
            }
        }
    }
}

// ─── ПРЕВЬЮ ─────────────────────────────────────────────────
// #if DEBUG / #endif — этот код компилируется только в режиме разработки.
// В финальной сборке приложения его нет вообще.
//
// #Preview — кнопка в Xcode, которая показывает экран без запуска на телефоне.
// Очень удобно: правишь код — превью обновляется мгновенно.
#if DEBUG
#Preview {
    RootMenuView(features: [
        PreviewFeature(id: "outages",    title: "Світло",     symbolName: "bolt.fill"),
        PreviewFeature(id: "books",      title: "Аудиокниги", symbolName: "headphones"),
        PreviewFeature(id: "debug",      title: "Debug",      symbolName: "ladybug"),
    ])
}

// Заглушка функции специально для превью: не делает реальных запросов.
@MainActor
private final class PreviewFeature: AppFeature {
    let id: FeatureID
    let title: String
    let symbolName: String
    init(id: String, title: String, symbolName: String) {
        self.id = id; self.title = title; self.symbolName = symbolName
    }
    // Просто показываем текст вместо реального экрана
    func makeRootView() -> AnyView { AnyView(Text(title)) }
}
#endif
