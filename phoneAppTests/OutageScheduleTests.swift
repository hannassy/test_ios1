// phoneAppTests/OutageScheduleTests.swift
//
// ═══════════════════════════════════════════════════════════
// ТЕСТЫ РАСЧЁТА ГРАФИКА
// ═══════════════════════════════════════════════════════════
//
// ЧТО ТАКОЕ ТЕСТ:
//   Тест — функция, которая вызывает наш код с известными входными данными
//   и проверяет, что результат соответствует ожиданию.
//
//   Если тест падает — значит что-то сломалось (или тест написан неверно).
//   Запускаем тесты в Xcode через ⌘U или кнопкой ▶ рядом с тестом.
//
// ЗАЧЕМ ТЕСТЫ БЕЗ СЕТИ:
//   Наша логика расчёта (slotIndex, currentStatus) не зависит от интернета.
//   Мы передаём фиктивные данные и проверяем результат.
//   Тест работает всегда — даже офлайн, даже в CI.
//
// @testable import phoneApp — импортирует приложение с доступом к internal-типам.
// Без @testable мы бы видели только public API.

import Testing
import Foundation
@testable import phoneApp

struct OutageScheduleTests {

    // ─── Вспомогательная функция ─────────────────────────────────────────────

    /// Создаёт снимок с заданными слотами для одного дня.
    /// Используем вместо реальных данных с сети — тест полностью предсказуем.
    private func makeSnapshot(factSlots: [String: SlotStatus], day: String) -> OutageSnapshot {
        let place = SavedPlace(
            id: UUID(), label: "Тест", region: .odesa,
            city: "Одеса", street: "вул. Тестова", house: "1", group: "GPV3.1"
        )
        return OutageSnapshot(
            place: place,
            factSchedule: [day: factSlots],
            presetSchedule: [:],
            fetchedAt: .now
        )
    }


    // ─── Тесты ───────────────────────────────────────────────────────────────

    // @Test — атрибут Swift Testing (фреймворк тестов, встроенный в Swift 6).
    // В скобках — описание теста. Появится в отчёте Xcode.

    @Test("Слот 0 (00:00) возвращает статус ON")
    func slotZeroIsOn() {
        let day = "2026-10-31"
        // Чётные слоты — свет есть, нечётные — нет.
        var slots: [String: SlotStatus] = [:]
        (0..<48).forEach { slots["\($0)"] = $0 % 2 == 0 ? .on : .off }

        let snapshot = makeSnapshot(factSlots: slots, day: day)

        // Создаём конкретную дату: полночь 31 октября по Киеву.
        // Без явного часового пояса — тест зависел бы от часового пояса устройства.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 31
        comps.hour = 0; comps.minute = 0
        comps.timeZone = TimeZone(identifier: "Europe/Kyiv")
        let midnight = Calendar.current.date(from: comps)!

        let status = snapshot.currentStatus(at: midnight)

        // #expect — проверяет условие. Если false — тест падает с сообщением.
        #expect(status.currentSlot == .on)
        #expect(status.source == .fact)
    }

    @Test("Слот 1 (00:30) возвращает статус OFF")
    func slotOneIsOff() {
        let day = "2026-10-31"
        var slots: [String: SlotStatus] = [:]
        (0..<48).forEach { slots["\($0)"] = $0 % 2 == 0 ? .on : .off }

        let snapshot = makeSnapshot(factSlots: slots, day: day)

        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 31
        comps.hour = 0; comps.minute = 30
        comps.timeZone = TimeZone(identifier: "Europe/Kyiv")
        let halfPast = Calendar.current.date(from: comps)!

        let status = snapshot.currentStatus(at: halfPast)
        // 00:30 = слот 1, нечётный → .off
        #expect(status.currentSlot == .off)
    }

    @Test("Следующее переключение: из слота 0 (ON) на слот 1 (OFF)")
    func nextChangeFromSlotZeroToOne() {
        let day = "2026-10-31"
        // Только слот 0 — on, остальные — off
        var slots: [String: SlotStatus] = [:]
        (0..<48).forEach { slots["\($0)"] = $0 == 0 ? .on : .off }

        let snapshot = makeSnapshot(factSlots: slots, day: day)

        // 00:15 — середина слота 0. Следующее переключение должно быть в 00:30.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 31
        comps.hour = 0; comps.minute = 15
        comps.timeZone = TimeZone(identifier: "Europe/Kyiv")
        let date = Calendar.current.date(from: comps)!

        let status = snapshot.currentStatus(at: date)
        #expect(status.nextChange != nil)

        let changeHour = Calendar.current.component(.hour,   from: status.nextChange!)
        let changeMin  = Calendar.current.component(.minute, from: status.nextChange!)
        // Должно быть ровно 00:30
        #expect(changeHour == 0)
        #expect(changeMin  == 30)
    }

    @Test("Нет данных на этот день — статус unknown, source noData")
    func noDataForDay() {
        let place = SavedPlace(
            id: UUID(), label: "X", region: .kyiv,
            city: "Київ", street: "вул. X", house: "1", group: "G"
        )
        // Пустые словари — нет ни fact, ни preset
        let snapshot = OutageSnapshot(
            place: place, factSchedule: [:], presetSchedule: [:], fetchedAt: .now
        )
        let status = snapshot.currentStatus(at: .now)
        #expect(status.currentSlot == .unknown)
        #expect(status.source == .noData)
    }

    @Test("Preset используется, когда fact пустой")
    func presetFallback() {
        let day = "2026-10-31"
        // Все слоты — maybe (прогнозный статус)
        var slots: [String: SlotStatus] = [:]
        (0..<48).forEach { slots["\($0)"] = .maybe }

        let place = SavedPlace(
            id: UUID(), label: "T", region: .odesa,
            city: "Одеса", street: "вул. Т", house: "1", group: "G"
        )
        // fact пустой, preset заполнен
        let snapshot = OutageSnapshot(
            place: place, factSchedule: [:], presetSchedule: [day: slots], fetchedAt: .now
        )

        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 31; comps.hour = 12; comps.minute = 0
        comps.timeZone = TimeZone(identifier: "Europe/Kyiv")
        let date = Calendar.current.date(from: comps)!

        let status = snapshot.currentStatus(at: date)
        #expect(status.currentSlot == .maybe)
        #expect(status.source == .preset)  // Использовался preset, не fact
    }

    @Test("slotIndex: час 12, минута 45 → слот 25")
    func slotIndexCalculation() {
        // Формула: 12 * 2 + 1 = 25 (минута 45 ≥ 30 → прибавляем 1)
        var comps = DateComponents()
        comps.hour = 12; comps.minute = 45
        let date = Calendar.current.date(from: comps)!
        #expect(OutageSnapshot.slotIndex(for: date) == 25)
    }
}
