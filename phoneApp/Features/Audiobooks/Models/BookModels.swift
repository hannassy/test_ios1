// Features/Audiobooks/Models/BookModels.swift
//
// ═══════════════════════════════════════════════════════════
// МОДЕЛИ ДАННЫХ — ФУНКЦИЯ «АУДИОКНИГИ»
// ═══════════════════════════════════════════════════════════
//
// Модели этого модуля изолированы: ни OutageModels.swift, ни DiagnosticLog.swift
// ничего не знают об AudioBook. Это намеренно — каждый раздел независим.

import Foundation


// ─── КНИГА ───────────────────────────────────────────────────────────────────

/// Метаданные одной аудиокниги.
/// Сами аудиофайлы лежат на диске — здесь только описание.
struct AudioBook: Codable, Identifiable, Sendable, Equatable {
    var id: UUID              // Уникальный идентификатор (UUID генерируется при импорте)
    var title: String         // Название книги (из имени ZIP-архива или m4b-метаданных)
    var author: String        // Автор (пока заполняется пустой строкой, можно редактировать)
    var folderName: String    // Имя папки внутри Documents/AudioBooks/ (= UUID.uuidString)
    var coverFileName: String? // Имя файла обложки внутри папки книги (jpg/png)
    var chapters: [Chapter]   // Список глав
    var addedAt: Date         // Когда добавлена

    /// Одна глава книги.
    /// Вложенный тип — Chapter имеет смысл только в контексте AudioBook.
    struct Chapter: Codable, Identifiable, Sendable, Equatable {
        var id: UUID
        var title: String       // Название главы (из метаданных m4b или имени mp3-файла)
        var fileName: String    // Имя аудиофайла относительно папки книги
        var duration: TimeInterval  // Длительность в секундах
        var index: Int          // Порядковый номер (0-based)
    }
}


// ─── ПРОГРЕСС ─────────────────────────────────────────────────────────────────

/// Прогресс воспроизведения — отдельная от книги структура.
///
/// Зачем отдельно, а не поле в AudioBook:
///   AudioBook — метаданные (меняются редко).
///   BookProgress — состояние (меняется каждые полсекунды во время воспроизведения).
///   Разделение позволяет сохранять прогресс часто, не перезаписывая всю книгу.
struct BookProgress: Codable, Sendable {
    var bookID: UUID          // К какой книге относится
    var chapterIndex: Int     // Номер текущей главы
    var position: TimeInterval // Позиция внутри главы (секунды)
    var updatedAt: Date       // Когда последний раз обновлялся
}
