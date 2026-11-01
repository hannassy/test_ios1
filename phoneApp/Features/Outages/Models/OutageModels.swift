// Features/Outages/Models/OutageModels.swift
//
// ═══════════════════════════════════════════════════════════
// МОДЕЛИ ДАННЫХ — ФУНКЦИЯ «СВІТЛО»
// ═══════════════════════════════════════════════════════════
//
// Модели — это просто структуры с данными, без логики отображения.
// Разделяем данные и UI: если поменяется сайт ДТЭК — меняем только
// парсер в DtekAjaxClient, не трогая экраны.
//
// КАК ДТЭК ХРАНИТ ГРАФИК:
//   День разбит на 48 получасовых слотов (0–47).
//   Слот 0 = 00:00–00:30, слот 1 = 00:30–01:00, ..., слот 47 = 23:30–24:00.
//   Каждый слот имеет статус: свет есть / нет / возможно.
//   Есть два расписания:
//     - fact  : подтверждённый график на сегодня/завтра (обновляется в течение дня)
//     - preset: прогнозный план на неделю (менее точный)

import Foundation


// ─── СОХРАНЁННЫЙ АДРЕС ───────────────────────────────────────────────────────

/// Одно сохранённое место пользователя: дом, родители и т.д.
///
/// struct (структура), а не class:
///   - Передаётся по значению (копируется, не ссылается).
///   - Безопасно в многопоточном коде — у каждого потока своя копия.
///   - Хорошо подходит для данных-записей, не объектов с поведением.
struct SavedPlace: Codable, Identifiable, Sendable, Equatable {
    var id: UUID           // Уникальный ключ. UUID = случайный 128-битный идентификатор
    var label: String      // Пользовательское название: «Дом», «Родители», «Работа»
    var region: DtekRegion // Регион ДТЭК
    var city: String       // Город (украинским — как на сайте ДТЭК)
    var street: String     // Улица
    var house: String      // Номер дома
    var group: String      // Группа отключений: «GPV3.1», «GPV1» и т.д. Берётся с сайта.
}


// ─── СТАТУС СЛОТА ────────────────────────────────────────────────────────────

/// Статус одного получасового слота.
///
/// Наследование от String: rawValue совпадает со значением, которое
/// возвращает сайт ДТЭК в JSON («yes», «no», «maybe»).
/// Так можно декодировать из JSON одной строкой: SlotStatus(rawValue: str).
enum SlotStatus: String, Codable, Sendable {
    case on      = "yes"    // Електрика є (свет есть)
    case off     = "no"     // Відключення (свет выключен)
    case maybe   = "maybe"  // Можливо (может быть выключен — прогнозный)
    case unknown            // Нет данных (не приходило в ответе)

    /// Текст для отображения на экране.
    var displayName: String {
        switch self {
        case .on:      return "Світло є"
        case .off:     return "Немає"
        case .maybe:   return "Возможно"
        case .unknown: return "Неизвестно"
        }
    }
}

/// Расписание на один день: словарь «номер_слота → статус».
/// typealias — псевдоним для читабельности. Без него пришлось бы писать
/// [String: SlotStatus] везде, что менее понятно.
typealias DaySchedule = [String: SlotStatus]


// ─── ОТВЕТ САЙТА ДТЭК ────────────────────────────────────────────────────────

/// Разобранный ответ AJAX-запроса getHomeNum.
struct DtekScheduleResponse: Codable, Sendable {
    /// Подтверждённый график. Ключ: «2026-10-31», значение: расписание дня.
    let fact: [String: DaySchedule]

    /// Прогнозный недельный план. Вложенная структура:
    ///   группа → дата → расписание дня
    ///   Пример: ["GPV3.1": ["2026-10-31": [слоты...]]]
    let preset: [String: [String: DaySchedule]]

    /// Группа отключений для запрошенного дома (например «GPV3.1»).
    let group: String
}


// ─── СНИМОК ДЛЯ ВИДЖЕТА ──────────────────────────────────────────────────────

/// Данные, которые приложение сохраняет в App Group для виджета.
///
/// Зачем снимок:
///   Виджет — отдельный процесс, без доступа к памяти основного приложения.
///   Оба читают/пишут общую папку (App Group) через файловую систему.
///   Приложение пишет снимок → виджет читает его и строит timeline.
struct OutageSnapshot: Codable, Sendable {
    var place: SavedPlace
    var factSchedule: [String: DaySchedule]    // fact-данные из ответа
    var presetSchedule: [String: DaySchedule]  // preset для конкретной группы дома
    var fetchedAt: Date                        // Когда последний раз обновляли

    /// Создаёт снимок из сырого ответа ДТЭК.
    /// Из preset берём только расписание нужной группы (например GPV3.1).
    init(place: SavedPlace, response: DtekScheduleResponse, fetchedAt: Date) {
        self.place = place
        self.factSchedule = response.fact
        // response.group — «GPV3.1». Берём из preset только этот ключ.
        // ?? [:] — если группа не найдена, используем пустой словарь.
        self.presetSchedule = response.preset[response.group] ?? [:]
        self.fetchedAt = fetchedAt
    }
}


// ─── ТЕКУЩИЙ СТАТУС ──────────────────────────────────────────────────────────

/// Итоговый результат для отображения: что сейчас и когда изменится.
struct OutageStatus: Sendable {
    let currentSlot: SlotStatus  // Статус текущего слота
    let nextChange: Date?        // Когда начнётся следующий слот с другим статусом
    let source: StatusSource     // Откуда взяли данные (важно знать, насколько точно)

    /// Откуда взяты данные.
    enum StatusSource: Sendable {
        case fact    // Из подтверждённого графика — точно
        case preset  // Из прогноза — приблизительно
        case noData  // Нет данных совсем
    }
}


// ─── ВЫЧИСЛЕНИЕ ТЕКУЩЕГО СТАТУСА ─────────────────────────────────────────────

// extension — добавляем методы к уже существующему типу.
// Вынесено в extension, чтобы не смешивать «данные» и «логику расчёта» в одном блоке.
extension OutageSnapshot {

    /// Рассчитывает текущий статус по снимку для произвольного момента времени.
    /// По умолчанию — прямо сейчас.
    func currentStatus(at date: Date = .now) -> OutageStatus {
        let calendar = Calendar.current
        let dayKey = Self.dayKey(for: date)      // "2026-10-31"
        let slotIndex = Self.slotIndex(for: date) // 0..47

        // Приоритет: fact (точный) > preset (прогноз) > нет данных.
        if let daySchedule = factSchedule[dayKey] {
            return status(from: daySchedule, slotIndex: slotIndex, source: .fact, date: date, calendar: calendar)
        }
        if let daySchedule = presetSchedule[dayKey] {
            return status(from: daySchedule, slotIndex: slotIndex, source: .preset, date: date, calendar: calendar)
        }
        return OutageStatus(currentSlot: .unknown, nextChange: nil, source: .noData)
    }

    /// Вычисляет статус текущего слота и время следующего переключения.
    private func status(
        from schedule: DaySchedule,
        slotIndex: Int,
        source: OutageStatus.StatusSource,
        date: Date,
        calendar: Calendar
    ) -> OutageStatus {
        let current = schedule[String(slotIndex)] ?? .unknown

        // Ищем ближайший слот, где статус отличается от текущего.
        var next: Date?
        for i in (slotIndex + 1)..<48 {
            if let s = schedule[String(i)], s != current {
                next = slotStartDate(index: i, base: date, calendar: calendar)
                break
            }
        }
        return OutageStatus(currentSlot: current, nextChange: next, source: source)
    }

    /// Номер получасового слота для данного момента: 0–47.
    /// Формула: час * 2 + (0 если минута < 30, 1 если ≥ 30).
    /// Пример: 14:45 → 14 * 2 + 1 = 29.
    static func slotIndex(for date: Date) -> Int {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return h * 2 + (m >= 30 ? 1 : 0)
    }

    /// Дата в формате "YYYY-MM-DD" по киевскому времени.
    /// Важно указывать конкретный часовой пояс (Europe/Kyiv):
    /// без него устройство использует часовой пояс пользователя,
    /// что приведёт к ошибкам, если телефон настроен на другой регион.
    static func dayKey(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Kyiv")
        return fmt.string(from: date)
    }

    /// Дата начала слота с заданным индексом.
    /// Например, слот 29 → 14:30 текущего дня.
    private func slotStartDate(index: Int, base: Date, calendar: Calendar) -> Date {
        let h = index / 2      // Целая часть = час
        let m = (index % 2) * 30  // Остаток: 0 → 0 мин, 1 → 30 мин
        var comps = calendar.dateComponents([.year, .month, .day], from: base)
        comps.hour = h
        comps.minute = m
        comps.second = 0
        return calendar.date(from: comps) ?? base
    }
}
