// Features/Outages/Services/OutageViewModel.swift
//
// ═══════════════════════════════════════════════════════════
// VIEWMODEL — СВЯЗУЮЩЕЕ ЗВЕНО МЕЖДУ ДАННЫМИ И ЭКРАНОМ
// ═══════════════════════════════════════════════════════════
//
// ПАТТЕРН MVVM (Model-View-ViewModel):
//   Model      — данные: OutageSnapshot, SavedPlace, SlotStatus
//   View       — экран: OutagesRootView, DayScheduleView и т.д.
//   ViewModel  — этот файл: бизнес-логика и состояние экрана
//
//   Зачем отделять ViewModel от View:
//     - View превращается в простой «рендерер» состояния.
//     - ViewModel тестируется без запуска интерфейса.
//     - Логику «что делать при ошибке» легко менять не трогая вёрстку.
//
// @Observable — при изменении любого свойства SwiftUI перерисует подписанные вью.
// @MainActor  — все обновления свойств происходят на главном потоке.

import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "app.local.phoneapp", category: "OutageViewModel")

@MainActor
@Observable
final class OutageViewModel {

    // ─── Состояние экрана ────────────────────────────────────────────────────
    // Всё, что видит пользователь — здесь. View читает эти свойства и рисует UI.

    var snapshot: OutageSnapshot?         // Последний скачанный снимок с графиком
    var currentStatus: OutageStatus?      // Текущий статус (свет есть / нет / возможно)
    var isLoading = false                 // Показывать ли спиннер загрузки
    var error: String?                    // Текст ошибки для баннера (nil = нет ошибки)
    var streetSuggestions: [String] = []  // Подсказки улиц при добавлении адреса
    var houseSuggestions: [String: String] = [:]  // дом → группа (для мастера адреса)


    // ─── Зависимости ─────────────────────────────────────────────────────────
    // Получены снаружи — можно подменить в тестах.

    private let client: any DtekClientProtocol   // Сетевой клиент (или заглушка)
    private let addressStore: AddressStore        // Список сохранённых адресов
    private let diagnostics: any DiagnosticRecording  // Журнал ошибок


    // ─── Внутренние задачи ───────────────────────────────────────────────────
    // Task — единица асинхронной работы. Храним ссылки, чтобы отменять при необходимости.

    private var fetchTask: Task<Void, Never>?   // Задача загрузки графика
    private var streetTask: Task<Void, Never>?  // Задача поиска улиц


    // ─── Инициализация ───────────────────────────────────────────────────────

    init(
        client: any DtekClientProtocol,
        addressStore: AddressStore = .shared,
        diagnostics: any DiagnosticRecording
    ) {
        self.client = client
        self.addressStore = addressStore
        self.diagnostics = diagnostics

        // Пока не загрузили свежие данные — показываем последний сохранённый снимок.
        // Пользователь видит хоть что-то сразу, не пустой экран.
        if let saved = WidgetSnapshotStore.load(),
           saved.place.id == addressStore.selectedPlaceID {
            self.snapshot = saved
            self.currentStatus = saved.currentStatus()
        }
    }


    // ─── Публичные методы (вызываются из View) ───────────────────────────────

    /// Загружает свежий график для выбранного адреса.
    /// Отменяет предыдущий незавершённый запрос перед новым.
    func refresh() {
        guard let place = addressStore.selectedPlace else { return }
        fetchTask?.cancel()  // Отменяем предыдущий запрос (если ещё не завершён)
        fetchTask = Task { await fetch(place: place) }
    }

    /// Переключает выбранное место и загружает для него график.
    func selectPlace(id: UUID) {
        addressStore.select(id: id)
        refresh()
    }

    /// Поиск улиц с дебаунсом.
    ///
    /// Дебаунс — задержка перед выполнением. Пользователь печатает «вул. Юності».
    /// Без дебаунса каждая буква запускала бы сетевой запрос (очень много запросов).
    /// С дебаунсом: ждём 400 мс после последней буквы, потом один запрос.
    func searchStreets(region: DtekRegion, city: String, query: String) {
        // Отменяем предыдущий поиск (пользователь ещё не закончил вводить).
        streetTask?.cancel()

        // Короткий запрос (< 2 символов) — не ищем, слишком много результатов.
        guard query.count >= 2 else { streetSuggestions = []; return }

        streetTask = Task {
            // Ждём 400 мс. Если за это время вызвали cancel() — выходим.
            try? await Task.sleep(nanoseconds: 400_000_000) // 400_000_000 наносекунд = 0.4 с
            guard !Task.isCancelled else { return }

            do {
                diagnostics.recordStep(feature: "outages", operation: "searchStreets")
                let all = try await client.fetchStreets(region: region, city: city)
                // Фильтруем клиентски: ищем подстроку без учёта регистра.
                streetSuggestions = all.filter { $0.localizedCaseInsensitiveContains(query) }
            } catch {
                log.error("Street search failed: \(error)")
                // Не показываем ошибку пользователю — просто нет подсказок.
            }
        }
    }

    /// Загружает список домов для улицы.
    func fetchHouses(region: DtekRegion, city: String, street: String) async {
        do {
            diagnostics.recordStep(feature: "outages", operation: "fetchHouses")
            houseSuggestions = try await client.fetchHouses(region: region, city: city, street: street)
        } catch {
            log.error("House fetch failed: \(error)")
        }
    }


    // ─── Внутренняя логика ───────────────────────────────────────────────────

    /// Основной метод загрузки: скачивает график и сохраняет для виджета.
    private func fetch(place: SavedPlace) async {
        // Защита от двойного запроса.
        guard !isLoading else { return }
        isLoading = true
        error = nil
        diagnostics.recordStep(feature: "outages", operation: "fetchSchedule")

        // defer — выполнится в конце функции при любом исходе (успех или ошибка).
        defer { isLoading = false }

        do {
            let response = try await client.fetchSchedule(for: place)
            let snap = OutageSnapshot(place: place, response: response, fetchedAt: .now)

            // Обновляем состояние — SwiftUI автоматически перерисует экран.
            self.snapshot = snap
            self.currentStatus = snap.currentStatus()

            // Сохраняем снимок в App Group — виджет обновится.
            try WidgetSnapshotStore.save(snap)

        } catch {
            log.error("Fetch schedule failed: \(error)")
            self.error = error.localizedDescription

            // Пишем подробный отчёт в журнал Debug.
            let report = DiagnosticReport(
                feature: "outages",
                operation: "fetchSchedule",
                error: error,
                userMessage: error.localizedDescription,
                context: [
                    "region":   place.region.rawValue,
                    "placeID":  place.id.uuidString,
                    "city":     place.city,
                    "street":   place.street,
                    "house":    place.house,
                ]
            )
            diagnostics.recordError(report)
        }
    }
}
