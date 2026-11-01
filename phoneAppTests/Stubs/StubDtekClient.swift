// phoneAppTests/Stubs/StubDtekClient.swift
//
// ═══════════════════════════════════════════════════════════
// ЗАГЛУШКА КЛИЕНТА ДТЭК ДЛЯ ТЕСТОВ
// ═══════════════════════════════════════════════════════════
//
// «Stub» (заглушка) — тестовый двойник, который заменяет реальный объект.
// StubDtekClient реализует DtekClientProtocol, но не ходит в сеть.
// Возвращает заранее заданные данные или бросает ошибку по команде.
//
// Использование:
//   let stub = StubDtekClient(shouldThrow: true)
//   let vm = OutageViewModel(client: stub, ...)
//   // Теперь vm будет получать ошибки без реального интернета
//
// Это называется «инверсия зависимостей» (Dependency Injection):
// вместо создания DtekAjaxClient внутри ViewModel, мы передаём его снаружи.
// В тестах подаём заглушку, в продакшне — реальный клиент.

import Foundation
@testable import phoneApp

struct StubDtekClient: DtekClientProtocol {
    // Настраиваемые данные, которые будет возвращать заглушка
    var streets: [String] = ["вул. Тестова", "вул. Прикладна"]
    var houses: [String: String] = ["1": "GPV3.1", "2": "GPV3.2"]
    var scheduleResponse: DtekScheduleResponse?  // nil = возвращать стандартный ответ

    // Если true — все методы будут бросать StubError.forced
    var shouldThrow = false

    func fetchStreets(region: DtekRegion, city: String) async throws -> [String] {
        if shouldThrow { throw StubError.forced }
        return streets
    }

    func fetchHouses(region: DtekRegion, city: String, street: String) async throws -> [String: String] {
        if shouldThrow { throw StubError.forced }
        return houses
    }

    func fetchSchedule(for place: SavedPlace) async throws -> DtekScheduleResponse {
        if shouldThrow { throw StubError.forced }
        if let r = scheduleResponse { return r }

        // Стандартный ответ: всё светло весь день
        var day = DaySchedule()
        (0..<48).forEach { day["\($0)"] = .on }
        let today = OutageSnapshot.dayKey(for: .now)
        return DtekScheduleResponse(fact: [today: day], preset: [:], group: "GPV3.1")
    }

    /// Тестовая ошибка — проще enum чем реальный DtekError
    enum StubError: Error {
        case forced  // «Принудительная» ошибка для тестирования обработки ошибок
    }
}
