// Features/Outages/Services/DtekAjaxClient.swift
//
// ═══════════════════════════════════════════════════════════
// КЛИЕНТ ДТЭК — РЕАЛЬНЫЕ ЗАПРОСЫ К САЙТУ
// ═══════════════════════════════════════════════════════════
//
// КАК РАБОТАЕТ САЙТ ДТЭК:
//   Это WordPress-сайт. Страница графика отправляет запросы к
//   собственному AJAX-эндпоинту (/ua/ajax). Мы делаем то же самое.
//
//   Шаг 1: Получить cookies через WKWebView (обход WAF-защиты).
//   Шаг 2: POST /ua/ajax с method=getStreets → список улиц.
//   Шаг 3: POST /ua/ajax с method=getHomeNum → дома + группа + расписание.
//
// ЧТО ТАКОЕ WAF:
//   Incapsula/Imperva — защита от ботов. Проверяет, что запрос идёт
//   от реального браузера. URLSession «не похож» на браузер.
//   Решение: сначала загружаем страницу через WKWebView (настоящий браузер),
//   получаем cookies проверки, потом используем их в URLSession.
//
// actor — потокобезопасный тип. cookieCache и session защищены автоматически.

import Foundation
import WebKit
import OSLog

private let log = Logger(subsystem: "app.local.phoneapp", category: "DtekClient")

actor DtekAjaxClient: DtekClientProtocol {

    // Кэш cookies по региону. Когда первый раз обращаемся к региону,
    // загружаем cookies через WKWebView и кэшируем.
    // При следующих запросах берём из кэша — быстрее и экономим батарею.
    private var cookieCache: [DtekRegion: [HTTPCookie]] = [:]

    // URLSession — стандартный HTTP-клиент iOS. Аналог curl или fetch.
    private var session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15   // Ждём ответ не дольше 15 сек
        config.timeoutIntervalForResource = 30  // Весь ресурс не дольше 30 сек
        self.session = URLSession(configuration: config)
    }


    // ─── DtekClientProtocol ──────────────────────────────────────────────────

    func fetchStreets(region: DtekRegion, city: String) async throws -> [String] {
        // Формируем тело запроса в формате application/x-www-form-urlencoded.
        // Это как поля формы в браузере: key=value&key2=value2.
        let body = "method=getStreets&data[0][name]=city&data[0][value]=\(city.urlEncoded)"
        let raw = try await post(to: region.ajaxURL, region: region, body: body)
        return try parseStreets(from: raw)
    }

    func fetchHouses(region: DtekRegion, city: String, street: String) async throws -> [String: String] {
        // UNIX timestamp — секунды с 1970-01-01. Сайт ДТЭК требует его
        // как параметр updateFact, чтобы получить актуальные данные (не кэшированные).
        let timestamp = Int(Date().timeIntervalSince1970)
        let body = [
            "method=getHomeNum",
            "data[0][name]=city&data[0][value]=\(city.urlEncoded)",
            "data[1][name]=street&data[1][value]=\(street.urlEncoded)",
            "data[2][name]=updateFact&data[2][value]=\(timestamp)",
        ].joined(separator: "&")
        let raw = try await post(to: region.ajaxURL, region: region, body: body)
        return try parseHouses(from: raw)
    }

    func fetchSchedule(for place: SavedPlace) async throws -> DtekScheduleResponse {
        let timestamp = Int(Date().timeIntervalSince1970)
        let body = [
            "method=getHomeNum",
            "data[0][name]=city&data[0][value]=\(place.city.urlEncoded)",
            "data[1][name]=street&data[1][value]=\(place.street.urlEncoded)",
            "data[2][name]=updateFact&data[2][value]=\(timestamp)",
        ].joined(separator: "&")

        let raw = try await post(to: place.region.ajaxURL, region: place.region, body: body)
        return try parseSchedule(from: raw, house: place.house)
    }


    // ─── Сетевой слой ────────────────────────────────────────────────────────

    /// Выполняет POST-запрос с нужными заголовками и cookies.
    private func post(to url: URL, region: DtekRegion, body: String) async throws -> Data {
        // Убеждаемся, что у нас есть cookies WAF.
        let cookies = try await ensureCookies(for: region)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Заголовки, которые ожидает сайт ДТЭК.
        // Content-Type говорит серверу: «тело запроса — это данные формы».
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        // X-Requested-With: XMLHttpRequest — признак AJAX-запроса (WordPress ждёт его).
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        // Referer и Origin — говорим, что запрос «пришёл» со страницы графика.
        request.setValue(region.scheduleURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(region.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        // User-Agent — представляемся мобильным Safari. WAF меньше подозревает.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        // Преобразуем cookies в заголовок "Cookie: name=value; name2=value2".
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
        cookieHeader.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // Тело запроса — строка в UTF-8.
        request.httpBody = body.data(using: .utf8)

        log.debug("POST \(url.absoluteString)")
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DtekError.invalidResponse
        }
        log.debug("Response \(http.statusCode) from \(url.absoluteString)")

        // Проверяем: вдруг вместо JSON нам вернули HTML-страницу проверки WAF?
        // Признак: ответ начинается с "<" (это HTML-тег, не JSON).
        if http.statusCode == 200,
           let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespaces).hasPrefix("<") {
            log.warning("WAF HTML detected, refreshing cookies for \(region.rawValue)")
            // Старые cookies протухли — сбрасываем кэш и получаем новые.
            cookieCache.removeValue(forKey: region)
            let fresh = try await ensureCookies(for: region)
            var req2 = request
            let h2 = HTTPCookie.requestHeaderFields(with: fresh)
            h2.forEach { req2.setValue($1, forHTTPHeaderField: $0) }
            let (data2, _) = try await session.data(for: req2)
            return data2
        }
        return data
    }

    /// Возвращает cookies для региона: из кэша или загружает через WKWebView.
    private func ensureCookies(for region: DtekRegion) async throws -> [HTTPCookie] {
        // Есть в кэше — возвращаем сразу (без сети и без WKWebView).
        if let cached = cookieCache[region], !cached.isEmpty {
            return cached
        }
        // Кэш пустой — нужно открыть страницу через настоящий браузер.
        // MainActor.run переключается на главный поток (WKWebView требует его).
        let cookies = try await MainActor.run {
            try WKCookieFetcher.fetchCookies(from: region.scheduleURL)
        }
        cookieCache[region] = cookies
        return cookies
    }


    // ─── Разбор JSON ─────────────────────────────────────────────────────────

    /// Разбирает ответ getStreets: возвращает отсортированный список улиц.
    private func parseStreets(from data: Data) throws -> [String] {
        // Локальная структура для декодирования — не нужна снаружи этого метода.
        struct Resp: Decodable {
            let result: Bool
            let streets: [String: [String]]?  // Ключ — название города, массив — улицы
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard resp.result else { throw DtekError.serverError }
        // flatMap собирает все улицы из всех городов в один массив.
        return (resp.streets?.values.flatMap { $0 } ?? []).sorted()
    }

    /// Разбирает ответ getHomeNum для списка домов: возвращает словарь дом → группа.
    private func parseHouses(from data: Data) throws -> [String: String] {
        struct Entry: Decodable {
            let sub_type_reason: [String]?  // Массив групп, например ["GPV3.1"]
        }
        struct Resp: Decodable {
            let result: Bool
            let data: [String: Entry]?  // Ключ — номер дома («1», «1А»...)
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard resp.result, let entries = resp.data else { throw DtekError.serverError }
        // reduce(into:) — как forEach, но строит словарь.
        // Берём первую группу из массива (основная группа дома).
        return entries.reduce(into: [:]) { acc, pair in
            acc[pair.key] = pair.value.sub_type_reason?.first ?? "?"
        }
    }

    /// Разбирает полный ответ getHomeNum: дома, группы, fact и preset расписания.
    private func parseSchedule(from data: Data, house: String) throws -> DtekScheduleResponse {
        struct Entry: Decodable {
            let sub_type_reason: [String]?
        }
        // Сырой JSON имеет статусы как строки ("yes", "no", "maybe").
        // Сначала декодируем в строки, потом конвертируем в SlotStatus.
        struct RawResp: Decodable {
            let result: Bool
            let data: [String: Entry]?
            let preset: [String: [String: [String: String]]]?  // группа → дата → слот → строка
            let fact: [String: [String: String]]?               // дата → слот → строка
        }

        let resp = try JSONDecoder().decode(RawResp.self, from: data)
        guard resp.result else { throw DtekError.serverError }

        // Определяем группу конкретного дома (например «GPV3.1»).
        let group = resp.data?[house]?.sub_type_reason?.first ?? "?"

        // Конвертируем строки статусов в SlotStatus (enum).
        func convert(_ raw: [String: String]) -> DaySchedule {
            raw.reduce(into: DaySchedule()) { acc, pair in
                // SlotStatus(rawValue:) вернёт nil для неизвестных значений → .unknown.
                acc[pair.key] = SlotStatus(rawValue: pair.value) ?? .unknown
            }
        }

        let fact = (resp.fact ?? [:]).reduce(into: [String: DaySchedule]()) { acc, pair in
            acc[pair.key] = convert(pair.value)
        }
        let preset = (resp.preset ?? [:]).reduce(into: [String: [String: DaySchedule]]()) { acc, pair in
            acc[pair.key] = pair.value.reduce(into: [:]) { a, p in a[p.key] = convert(p.value) }
        }

        return DtekScheduleResponse(fact: fact, preset: preset, group: group)
    }
}


// ─── ОШИБКИ КЛИЕНТА ──────────────────────────────────────────────────────────

/// Ошибки, которые может выбросить DtekAjaxClient.
/// LocalizedError позволяет определить errorDescription — текст для пользователя.
enum DtekError: Error, LocalizedError {
    case invalidResponse   // Пришло что-то странное (не HTTP-ответ)
    case serverError       // Сервер вернул result: false
    case cookiesFailed     // WKWebView не смог загрузить страницу
    case noData            // Дом не найден в ответе

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Неожиданный ответ от сервера ДТЭК."
        case .serverError:     return "Сервер ДТЭК вернул ошибку."
        case .cookiesFailed:   return "Не удалось пройти проверку сайта ДТЭК."
        case .noData:          return "График для этого адреса не найден."
        }
    }
}


// ─── URL ENCODING ─────────────────────────────────────────────────────────────

// private extension — расширение доступно только внутри этого файла.
private extension String {
    /// Кодирует строку для использования в URL query параметрах.
    /// Например, «вул. Юності» → «%D0%B2%D1%83%D0%BB...»
    /// Без этого кириллица и пробелы сломают HTTP-запрос.
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
