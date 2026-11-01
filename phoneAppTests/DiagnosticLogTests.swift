// phoneAppTests/DiagnosticLogTests.swift
//
// Тесты журнала ошибок.
// Проверяем: поля заполнены, фрагмент обрезается, текст содержит нужные данные.
// Всё без диска и без сети — тестируем только модели.

import Testing
import Foundation
@testable import phoneApp

struct DiagnosticLogTests {

    // Минимальная ошибка для тестов
    struct TestError: Error { var localizedDescription = "test error" }

    @Test("Отчёт содержит все поля контекста")
    func reportContextFields() {
        let report = DiagnosticReport(
            feature: "outages",
            operation: "fetchSchedule",
            error: TestError(),
            userMessage: "Не удалось загрузить",
            context: ["region": "oem", "city": "Одеса"],
            serverFragment: nil
        )

        // Проверяем что поля правильно заполнены
        #expect(report.feature == "outages")
        #expect(report.operation == "fetchSchedule")
        #expect(report.context["region"] == "oem")
        #expect(report.context["city"] == "Одеса")
        #expect(report.userMessage == "Не удалось загрузить")

        // UUID должен быть не пустым
        #expect(!report.id.uuidString.isEmpty)
    }

    @Test("Фрагмент сервера обрезается до 2048 символов")
    func serverFragmentTruncated() {
        // Создаём строку длиной 4096 символов — больше лимита 2048
        let longString = String(repeating: "A", count: 4096)
        let report = DiagnosticReport(
            feature: "test", operation: "test",
            error: TestError(), userMessage: "test",
            context: [:], serverFragment: longString
        )

        // После обрезки: 2048 символов + "…" = 2049
        #expect(report.serverResponseFragment?.count ?? 0 <= 2049)
        // Обрезанный фрагмент должен заканчиваться на "…"
        #expect(report.serverResponseFragment?.hasSuffix("…") == true)
    }

    @Test("asPlainText содержит основные поля")
    func plainTextContainsFields() {
        let report = DiagnosticReport(
            feature: "audiobooks",
            operation: "unzip",
            error: TestError(),
            userMessage: "Архив повреждён",
            context: ["archiveName": "book.zip"],
            serverFragment: nil
        )

        let text = report.asPlainText()

        // Все важные поля должны быть в тексте для отправки в чат
        #expect(text.contains("audiobooks.unzip"))
        #expect(text.contains("Архив повреждён"))
        #expect(text.contains("archiveName"))
        #expect(text.contains("book.zip"))
    }

    @Test("Нет дублирующихся ID в нескольких отчётах")
    func uniqueIDs() {
        // UUID() должен генерировать уникальные значения
        let reports = (0..<10).map { i in
            DiagnosticReport(
                feature: "f", operation: "o\(i)",
                error: TestError(), userMessage: "m",
                context: [:], serverFragment: nil
            )
        }
        let ids = Set(reports.map { $0.id })
        // Все 10 id должны быть уникальными
        #expect(ids.count == 10)
    }
}
