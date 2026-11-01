// Features/Outages/Services/DtekClientProtocol.swift
//
// ═══════════════════════════════════════════════════════════
// ПРОТОКОЛ КЛИЕНТА ДТЭК
// ═══════════════════════════════════════════════════════════
//
// Зачем протокол, если есть конкретный DtekAjaxClient?
//
//   В тестах и превью Xcode мы не хотим делать реальные запросы к сайту ДТЭК:
//     - Тесты должны работать без интернета и за миллисекунды.
//     - Превью в Xcode должны показывать данные мгновенно.
//
//   Решение: ViewModel получает не DtekAjaxClient напрямую,
//   а «что-то реализующее DtekClientProtocol».
//   В реальном приложении — DtekAjaxClient (ходит в сеть).
//   В тестах — StubDtekClient (возвращает фиктивные данные).
//
// async throws — методы асинхронные и могут бросать ошибки.
//   async  → вызывается через await, не блокирует UI.
//   throws → при ошибке бросает Error, который нужно поймать через do/catch.

import Foundation

protocol DtekClientProtocol: Sendable {

    /// Возвращает список улиц в городе.
    /// Используется в мастере добавления адреса для подсказок.
    func fetchStreets(region: DtekRegion, city: String) async throws -> [String]

    /// Возвращает словарь дом → группа для улицы.
    /// Нужно, чтобы узнать, какая группа отключений у конкретного дома.
    func fetchHouses(region: DtekRegion, city: String, street: String) async throws -> [String: String]

    /// Возвращает полный график для конкретного адреса (fact + preset + группа).
    func fetchSchedule(for place: SavedPlace) async throws -> DtekScheduleResponse
}
