// App/DiagnosticLog.swift
//
// ═══════════════════════════════════════════════════════════
// ЖУРНАЛ ОШИБОК
// ═══════════════════════════════════════════════════════════
//
// Что делает этот файл:
//   - Держит в памяти кольцевой буфер последних ~30 шагов (что делало приложение).
//   - Когда происходит ошибка — сохраняет полный отчёт на диск,
//     включая буфер шагов (контекст до сбоя).
//   - Раздел Debug читает эти отчёты и показывает их на экране.
//
// КЛЮЧЕВАЯ КОНЦЕПЦИЯ — ACTOR:
// ───────────────────────────────────────────────────────────
// actor — специальный тип в Swift, который гарантирует:
//   к его данным обращается только один «поток» за раз.
//
// Без actor две параллельные задачи могут одновременно изменять
// один и тот же массив — и данные испортятся (race condition).
// actor решает это автоматически: все вызовы методов выстраиваются
// в очередь. Не нужны locks, мьютексы и другие низкоуровневые примитивы.
//
// КОЛЬЦЕВОЙ БУФЕР (ring buffer):
// ───────────────────────────────────────────────────────────
// Массив фиксированного размера (30 элементов), работающий по кругу.
// Когда он заполнен, новый элемент перезаписывает самый старый.
// Хранит только «хвост» истории — именно то, что нужно для диагностики.

import Foundation
import OSLog

// Системный логгер. Запись идёт в os_log — можно видеть в Console.app на Mac
// при подключённом телефоне. Категория "Diagnostics" помогает фильтровать.
private let osLog = Logger(subsystem: "app.local.phoneapp", category: "Diagnostics")


// ─── ПРОТОКОЛ ────────────────────────────────────────────────────────────────
//
// Функции пишут в журнал через этот протокол — не напрямую в DiagnosticLog.
// Зачем так:
//   - В тестах подменяем на заглушку (пустую реализацию без диска и сети).
//   - Реальные функции не привязаны к конкретному классу DiagnosticLog.
//
// Sendable — гарантия, что тип безопасно передавать между потоками (acторами).
protocol DiagnosticRecording: Sendable {
    /// Записывает шаг — что приложение собирается сделать.
    /// Шаги хранятся в памяти и прикладываются к отчёту при ошибке.
    func recordStep(feature: String, operation: String)

    /// Записывает отчёт об ошибке на диск.
    func recordError(_ report: DiagnosticReport)
}


// ─── МОДЕЛИ ──────────────────────────────────────────────────────────────────

/// Один шаг в истории (живёт только в памяти).
struct DiagnosticStep: Sendable {
    let feature: String    // например "outages"
    let operation: String  // например "fetchSchedule"
    let date: Date
}

/// Полный отчёт об ошибке, сохраняемый на диск в виде JSON.
/// Codable — умеет кодироваться в JSON и декодироваться из него.
/// Identifiable — у каждого отчёта уникальный id (нужно для List в SwiftUI).
struct DiagnosticReport: Codable, Identifiable, Sendable {
    var id: UUID               // Уникальный идентификатор отчёта
    var date: Date             // Когда произошла ошибка
    var appVersion: String     // Версия приложения (из Info.plist)
    var iosVersion: String     // Версия iOS устройства
    var deviceModel: String    // Модель iPhone (например, iPhone14,3)
    var feature: String        // Какая функция (outages / audiobooks)
    var operation: String      // Что делали (fetchSchedule / unzip)
    var userMessage: String    // Понятный текст для человека
    var technicalType: String  // Технический тип и описание ошибки для разработчика
    var context: [String: String]        // Дополнительные данные: адрес, код HTTP и т.д.
    var serverResponseFragment: String?  // Кусок ответа сервера (до 2 КБ)
    var recentSteps: [DiagnosticStepRecord] // Цепочка шагов до ошибки
}

/// Шаг, сохранённый внутри отчёта (Codable — нужно для JSON).
struct DiagnosticStepRecord: Codable, Sendable {
    var feature: String
    var operation: String
    var date: Date
}


// ─── РЕАЛИЗАЦИЯ ──────────────────────────────────────────────────────────────

/// Потокобезопасный журнал. actor гарантирует — никаких гонок данных.
actor DiagnosticLog: DiagnosticRecording {

    // Единственный экземпляр на всё приложение (синглтон).
    static let shared = DiagnosticLog()

    private let maxReports = 100       // Максимум отчётов в файле
    private let maxFileSizeKB = 512    // Максимальный размер файла журнала (512 КБ)
    private let ringCapacity = 30      // Размер кольцевого буфера шагов

    // Кольцевой буфер: массив шагов + индекс для следующей записи.
    private var ring: [DiagnosticStep] = []
    private var ringIndex = 0

    /// Путь к JSON-файлу журнала в папке Application Support.
    /// Application Support — правильное место для данных приложения:
    /// не видно пользователю, не очищается при удалении других файлов.
    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("diagnostic_log.json")
    }


    // ─── DiagnosticRecording ─────────────────────────────────────────────────

    // nonisolated — метод можно вызывать без ожидания actor'а.
    // Это нужно, потому что DiagnosticRecording — Sendable-протокол,
    // а его вызывают из разных мест. Внутри мы немедленно «переходим»
    // в actor через Task { await self._appendStep(...) }.
    nonisolated func recordStep(feature: String, operation: String) {
        let step = DiagnosticStep(feature: feature, operation: operation, date: .now)
        // Task { } запускает асинхронную задачу и немедленно возвращает управление.
        // Шаг добавится в буфер «чуть позже», что нас устраивает.
        Task { await self._appendStep(step) }
    }

    nonisolated func recordError(_ report: DiagnosticReport) {
        // Сразу пишем в системный лог (синхронно — это быстрая операция).
        osLog.error("[\(report.feature).\(report.operation)] \(report.technicalType): \(report.userMessage)")
        // Сохраняем на диск асинхронно, чтобы не блокировать UI.
        Task { await self._persist(report) }
    }


    // ─── Чтение (для экрана Debug) ───────────────────────────────────────────

    /// Загружает все сохранённые отчёты, отсортированные: новые сначала.
    func loadReports() async -> [DiagnosticReport] {
        _loadReportsSync()
    }

    /// Очищает журнал (удаляет файл).
    func clearReports() async throws {
        try FileManager.default.removeItem(at: fileURL)
    }


    // ─── Внутренние методы ───────────────────────────────────────────────────

    /// Читает JSON-файл и возвращает массив отчётов. Синхронная версия для внутреннего use.
    private func _loadReportsSync() -> [DiagnosticReport] {
        guard let data = try? Data(contentsOf: fileURL),
              let reports = try? JSONDecoder().decode([DiagnosticReport].self, from: data)
        else { return [] }
        return reports.sorted { $0.date > $1.date }  // Сначала новые
    }

    /// Добавляет шаг в кольцевой буфер.
    private func _appendStep(_ step: DiagnosticStep) {
        if ring.count < ringCapacity {
            // Буфер ещё не заполнен — просто добавляем в конец.
            ring.append(step)
        } else {
            // Буфер полон — перезаписываем старейший элемент.
            // ringIndex % ringCapacity даёт позицию самого старого элемента.
            ring[ringIndex % ringCapacity] = step
            ringIndex += 1
        }
    }

    /// Сохраняет отчёт на диск с учётом лимитов.
    private func _persist(_ report: DiagnosticReport) {
        var reports = _loadReportsSync()

        // Прикладываем цепочку шагов к отчёту (снимок на момент ошибки).
        var r = report
        r.recentSteps = _orderedSteps().map {
            DiagnosticStepRecord(feature: $0.feature, operation: $0.operation, date: $0.date)
        }

        // Новый отчёт в начало списка (новые первыми).
        reports.insert(r, at: 0)

        // Обрезаем по количеству.
        if reports.count > maxReports {
            reports = Array(reports.prefix(maxReports))
        }

        guard let data = try? JSONEncoder().encode(reports) else { return }

        // Обрезаем по размеру файла: если превышен лимит — удаляем старые отчёты.
        let sizeKB = data.count / 1024
        if sizeKB > maxFileSizeKB {
            var trimmed = reports
            while trimmed.count > 1,
                  let td = try? JSONEncoder().encode(trimmed),
                  td.count / 1024 > maxFileSizeKB {
                trimmed.removeLast()
            }
            if let td = try? JSONEncoder().encode(trimmed) {
                // .atomic — файл записывается во временный файл, потом атомарно переименовывается.
                // Защищает от повреждения при внезапном отключении питания.
                try? td.write(to: fileURL, options: .atomic)
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Восстанавливает правильный порядок шагов из кольцевого буфера.
    private func _orderedSteps() -> [DiagnosticStep] {
        if ring.count < ringCapacity {
            // Буфер не заполнен — все элементы уже в правильном порядке.
            return ring
        }
        // Буфер полон: ringIndex указывает на самый старый элемент.
        // Собираем: от start до конца + от начала до start.
        let start = ringIndex % ringCapacity
        return Array(ring[start...]) + Array(ring[..<start])
    }
}


// ─── УДОБНЫЙ ИНИЦИАЛИЗАТОР ОТЧЁТА ────────────────────────────────────────────

extension DiagnosticReport {

    /// Создаёт отчёт из ошибки и контекста.
    /// Автоматически собирает версию приложения, iOS и модель устройства.
    init(
        feature: String,
        operation: String,
        error: Error,
        userMessage: String,
        context: [String: String] = [:],
        serverFragment: String? = nil
    ) {
        let info = ProcessInfo.processInfo

        self.id = UUID()
        self.date = .now

        // Версия приложения из Info.plist (та, что видна в настройках).
        self.appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"

        // Версия iOS как строка, например "iOS 17.4.1".
        self.iosVersion = info.operatingSystemVersionString

        // Модель устройства через системный вызов uname().
        // Возвращает внутреннее имя: iPhone14,3, iPhone15,2 и т.д.
        self.deviceModel = {
            var systemInfo = utsname()
            uname(&systemInfo)
            return withUnsafeBytes(of: &systemInfo.machine) { ptr in
                let bytes = ptr.bindMemory(to: CChar.self)
                return String(cString: bytes.baseAddress!)
            }
        }()

        self.feature = feature
        self.operation = operation
        self.userMessage = userMessage

        // Технический тип: "DtekError: Сервер ДТЭК вернул ошибку."
        // Полезен для разработчика, чтобы найти конкретный case в коде.
        self.technicalType = String(describing: type(of: error)) + ": " + error.localizedDescription

        self.context = context

        // Обрезаем фрагмент ответа сервера до 2048 символов.
        // WAF-страница проверки может весить сотни КБ — не раздуваем журнал.
        if let frag = serverFragment, frag.count > 2048 {
            self.serverResponseFragment = String(frag.prefix(2048)) + "…"
        } else {
            self.serverResponseFragment = serverFragment
        }

        // Шаги добавятся позже, в DiagnosticLog._persist().
        self.recentSteps = []
    }

    /// Форматирует отчёт в одну строку текста для копирования в чат.
    /// Достаточно вставить в сообщение — по нему видно, что нужно починить.
    func asPlainText() -> String {
        var lines: [String] = [
            "=== Diagnostic Report ===",
            "Date: \(date)",
            "App: \(appVersion) | iOS: \(iosVersion) | Device: \(deviceModel)",
            "Feature: \(feature).\(operation)",
            "Error: \(technicalType)",
            "Message: \(userMessage)",
        ]

        if !context.isEmpty {
            lines.append("Context:")
            // Сортируем ключи для воспроизводимого порядка.
            for (k, v) in context.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(k): \(v)")
            }
        }

        if !recentSteps.isEmpty {
            lines.append("Recent steps:")
            for step in recentSteps {
                lines.append("  [\(step.date)] \(step.feature).\(step.operation)")
            }
        }

        if let frag = serverResponseFragment {
            lines.append("Server response fragment:")
            lines.append(frag)
        }

        lines.append("=========================")
        return lines.joined(separator: "\n")
    }
}
