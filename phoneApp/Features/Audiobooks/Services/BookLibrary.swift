// Features/Audiobooks/Services/BookLibrary.swift
//
// ═══════════════════════════════════════════════════════════
// БИБЛИОТЕКА КНИГ
// ═══════════════════════════════════════════════════════════
//
// Хранит список книг и прогресс чтения.
// Книги хранятся в UserDefaults (метаданные, маленькие).
// Сами аудиофайлы — в Documents/AudioBooks/ (большие, нельзя в UserDefaults).

import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "app.local.phoneapp", category: "BookLibrary")

@MainActor
@Observable
final class BookLibrary {

    // Ключи UserDefaults с версией схемы (_v1).
    private let booksKey    = "audiobooks_v1"
    private let progressKey = "audiobook_progress_v1"

    // private(set): читать можно снаружи (View перебирает books), менять — только внутри.
    private(set) var books: [AudioBook] = []

    // Прогресс: словарь UUID книги → прогресс.
    // Не публичный: доступ через progress(for:) и saveProgress(_:).
    private var progressMap: [UUID: BookProgress] = [:]

    init() {
        load()  // Восстанавливаем сохранённые данные при запуске
    }


    // ─── Управление книгами ───────────────────────────────────────────────────

    /// Добавляет книгу в библиотеку (после успешного импорта ZIP).
    func add(_ book: AudioBook) {
        books.append(book)
        saveBooks()
    }

    /// Удаляет книгу из библиотеки вместе с её прогрессом.
    /// Сами файлы на диске удаляет AudiobooksViewModel (у него есть путь к папке).
    func remove(id: UUID) {
        books.removeAll { $0.id == id }
        progressMap.removeValue(forKey: id)
        saveBooks()
        saveProgress()
    }


    // ─── Прогресс ─────────────────────────────────────────────────────────────

    /// Возвращает прогресс для книги. nil — если никогда не слушали.
    func progress(for bookID: UUID) -> BookProgress? {
        progressMap[bookID]
    }

    /// Сохраняет прогресс. Вызывается из AudioPlayer примерно раз в полсекунды.
    func saveProgress(_ progress: BookProgress) {
        progressMap[progress.bookID] = progress
        saveProgress()  // Пишем на диск (UserDefaults)
    }


    // ─── Persistence ─────────────────────────────────────────────────────────

    private func load() {
        // Восстанавливаем список книг.
        if let data = UserDefaults.standard.data(forKey: booksKey),
           let decoded = try? JSONDecoder().decode([AudioBook].self, from: data) {
            books = decoded
        }
        // Восстанавливаем прогресс.
        if let data = UserDefaults.standard.data(forKey: progressKey),
           let decoded = try? JSONDecoder().decode([UUID: BookProgress].self, from: data) {
            progressMap = decoded
        }
    }

    private func saveBooks() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        UserDefaults.standard.set(data, forKey: booksKey)
    }

    private func saveProgress() {
        guard let data = try? JSONEncoder().encode(progressMap) else { return }
        UserDefaults.standard.set(data, forKey: progressKey)
    }


    // ─── Файловая система ─────────────────────────────────────────────────────

    /// Папка для всех аудиокниг: Documents/AudioBooks/
    ///
    /// Documents — стандартная папка для пользовательских данных.
    /// Она:
    ///   - Не очищается iOS (в отличие от Caches).
    ///   - Включается в резервную копию iCloud (если пользователь включил).
    ///   - Доступна через приложение «Файлы» (если включить в Info.plist).
    static var audioBooksDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appending(path: "AudioBooks")
        // withIntermediateDirectories: true — создаёт промежуточные папки если нужно.
        // Не падает если папка уже существует.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Папка конкретной книги: Documents/AudioBooks/<UUID>/
    func bookDirectory(for book: AudioBook) -> URL {
        Self.audioBooksDirectory.appending(path: book.folderName)
    }
}
