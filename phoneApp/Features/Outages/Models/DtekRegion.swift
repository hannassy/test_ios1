// Features/Outages/Models/DtekRegion.swift
//
// ═══════════════════════════════════════════════════════════
// РЕГИОНЫ ДТЭК
// ═══════════════════════════════════════════════════════════
//
// ДТЭК — несколько отдельных компаний (Одесские сети, Днепровские и т.д.).
// У каждой свой сайт с графиком. Этот enum перечисляет все поддерживаемые.
//
// Почему enum, а не массив строк:
//   - Компилятор проверяет, что мы не опечатались в названии региона.
//   - В switch можно убедиться, что обработаны все случаи.
//   - Хранится как строка (rawValue) — удобно для JSON и URL.

import Foundation

/// Один регион ДТЭК = один сайт с графиком.
///
/// Наследование от String: rawValue каждого кейса — строка.
/// Используется как ключ в URL: dtek-oem.com.ua, dtek-dnem.com.ua и т.д.
///
/// CaseIterable — автоматически создаёт DtekRegion.allCases: массив всех кейсов.
/// Используем в Picker на экране добавления адреса.
///
/// Codable — умеет сохраняться в JSON (для UserDefaults и файлов).
/// Sendable — безопасно передавать между потоками (actor и MainActor).
/// Identifiable — каждый элемент имеет id (нужно для List и Picker в SwiftUI).
enum DtekRegion: String, CaseIterable, Codable, Sendable, Identifiable {
    case odesa        = "oem"   // ДТЭК Одеські електромережі
    case dnipro       = "dnem"  // ДТЭК Дніпровські електромережі
    case kyiv         = "kem"   // ДТЭК Київські електромережі (город)
    case kyivObl      = "krem"  // ДТЭК Київські регіональні (область)
    case donetsk      = "dem"   // ДТЭК Донецькі електромережі
    case zaporizhzhia = "zem"   // ДТЭК Запорізькі електромережі

    // Identifiable требует свойство id.
    // Используем rawValue — он уже уникален.
    var id: String { rawValue }

    /// Русскоязычное название для отображения в меню выбора.
    var displayName: String {
        switch self {
        case .odesa:         return "Одесса (ДТЭК)"
        case .dnipro:        return "Днепр (ДТЭК)"
        case .kyiv:          return "Киев (ДТЭК)"
        case .kyivObl:       return "Киевская обл. (ДТЭК)"
        case .donetsk:       return "Донецкая обл. (ДТЭК)"
        case .zaporizhzhia:  return "Запорожье (ДТЭК)"
        }
    }

    /// Корневой URL сайта региона.
    /// Восклицательный знак (!) — force unwrap. Здесь безопасен:
    /// URL из жёстко заданной строки всегда валиден.
    var baseURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://www.dtek-\(rawValue).com.ua")!
    }

    /// URL AJAX-эндпоинта WordPress. На него шлются POST-запросы с методом и параметрами.
    var ajaxURL: URL {
        baseURL.appending(path: "/ua/ajax")
    }

    /// URL страницы с графиком. Нужен для получения WAF-cookies через WKWebView.
    var scheduleURL: URL {
        baseURL.appending(path: "/ua/shutdowns")
    }
}
