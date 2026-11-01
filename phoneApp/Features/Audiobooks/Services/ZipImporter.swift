// Features/Audiobooks/Services/ZipImporter.swift
//
// ═══════════════════════════════════════════════════════════
// ИМПОРТ ZIP-АРХИВА С АУДИОКНИГОЙ
// ═══════════════════════════════════════════════════════════
//
// ПОЧЕМУ actor:
//   Распаковка ZIP и разбор метаданных — тяжёлые операции.
//   actor гарантирует, что они не будут выполняться на главном потоке,
//   не замораживая интерфейс.
//
// КАК РАБОТАЕТ ИМПОРТ:
//   1. Пользователь выбирает ZIP через FileImporter (стандартный диалог iOS).
//   2. ZipImporter создаёт уникальную папку Documents/AudioBooks/<UUID>/.
//   3. ZIPFoundation распаковывает архив по файлу — не в память целиком.
//      Это важно для больших книг: 500 МБ в RAM не влезут.
//   4. Находим аудиофайлы в папке и строим список глав.
//   5. Для m4b-файла пробуем прочитать главы из метаданных (AVFoundation).
//   6. Возвращаем готовую книгу — AudiobooksViewModel добавляет её в библиотеку.

import Foundation
import ZIPFoundation   // Сторонняя библиотека: github.com/weichsel/ZIPFoundation
import AVFoundation    // Фреймворк Apple для работы с медиафайлами
import OSLog

private let log = Logger(subsystem: "app.local.phoneapp", category: "ZipImporter")

actor ZipImporter {

    private let diagnostics: any DiagnosticRecording

    init(diagnostics: any DiagnosticRecording) {
        self.diagnostics = diagnostics
    }

    /// Импортирует ZIP по URL. progressHandler вызывается с прогрессом 0.0–1.0.
    ///
    /// @Sendable — замыкание безопасно передавать между потоками.
    /// Нужно потому что actor и MainActor — разные потоки.
    func importZip(from url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> AudioBook {
        diagnostics.recordStep(feature: "audiobooks", operation: "importZip")
        log.info("Importing ZIP: \(url.lastPathComponent)")

        let booksDir = BookLibrary.audioBooksDirectory
        let bookID = UUID()

        // Имя книги — из имени архива без расширения.
        // Пользователь может переименовать потом.
        let rawTitle = url.deletingPathExtension().lastPathComponent

        // Папка книги = UUID. Гарантирует уникальность, даже если два архива с одним именем.
        let folderName = "\(bookID.uuidString)"
        let bookDir = booksDir.appending(path: folderName)

        do {
            try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

            // Archive(url:accessMode:.read) — открывает архив только для чтения.
            // ZIPFoundation читает запись за записью, не загружая всё в память.
            let archive = try Archive(url: url, accessMode: .read)

            // Считаем общее количество записей для расчёта прогресса.
            let total = Double(archive.makeIterator().reduce(0) { acc, _ in acc + 1 })
            var count = 0.0

            for entry in archive {
                // entry.path — путь внутри архива (например «audiobook/chapter01.mp3»).
                let dest = bookDir.appending(path: entry.path)
                // archive.extract — распаковывает одну запись.
                _ = try archive.extract(entry, to: dest)
                count += 1
                let progress = count / max(total, 1)
                // Сообщаем UI о прогрессе распаковки.
                progressHandler(progress)
            }

        } catch {
            // Распаковка провалилась — удаляем неполную папку, чтобы не засорять диск.
            try? FileManager.default.removeItem(at: bookDir)

            // Пишем подробный отчёт в Debug-журнал.
            let report = DiagnosticReport(
                feature: "audiobooks",
                operation: "unzip",
                error: error,
                userMessage: "Не удалось распаковать архив «\(url.lastPathComponent)».",
                context: [
                    "archiveName": url.lastPathComponent,
                    "archiveSize": "\(fileSizeKB(url)) КБ",
                ]
            )
            diagnostics.recordError(report)
            throw ImportError.extractionFailed(error)
        }

        // Строим список глав из распакованных файлов.
        let chapters = try await buildChapters(from: bookDir)

        guard !chapters.isEmpty else {
            // В архиве не было аудиофайлов — удаляем пустую папку.
            try? FileManager.default.removeItem(at: bookDir)
            throw ImportError.noAudioFiles
        }

        let book = AudioBook(
            id: bookID,
            title: rawTitle,
            author: "",
            folderName: folderName,
            coverFileName: findCover(in: bookDir),  // Ищем файл обложки (jpg/png)
            chapters: chapters,
            addedAt: .now
        )

        log.info("Imported book \"\(rawTitle)\" with \(chapters.count) chapters")
        return book
    }


    // ─── Вспомогательные методы ───────────────────────────────────────────────

    /// Сканирует папку книги и строит список глав.
    private func buildChapters(from dir: URL) async throws -> [AudioBook.Chapter] {
        let fm = FileManager.default
        // Set: быстрый поиск по расширению (O(1) вместо O(n) для массива).
        let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav"]

        let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        let audioFiles = items
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }  // Порядок по имени файла

        // Специальный случай: один m4b — пробуем метаданные глав.
        // M4B (audiobook) формат поддерживает встроенные метаданные с названиями глав.
        if audioFiles.count == 1, audioFiles[0].pathExtension.lowercased() == "m4b" {
            if let chapters = await extractM4BChapters(from: audioFiles[0], dir: dir) {
                return chapters
            }
        }

        // Иначе: каждый файл = одна глава. Имя главы = имя файла без расширения.
        var result: [AudioBook.Chapter] = []
        for (i, file) in audioFiles.enumerated() {
            let duration = await audioDuration(url: file)
            let chapter = AudioBook.Chapter(
                id: UUID(),
                title: file.deletingPathExtension().lastPathComponent,
                fileName: file.lastPathComponent,
                duration: duration,
                index: i
            )
            result.append(chapter)
        }
        return result
    }

    /// Читает главы из метаданных m4b-файла через AVFoundation.
    ///
    /// AVURLAsset — представляет медиафайл. Поддерживает метаданные по стандарту ISO.
    /// loadChapterMetadataGroups — Apple API специально для аудиокниг.
    private func extractM4BChapters(from url: URL, dir: URL) async -> [AudioBook.Chapter]? {
        let asset = AVURLAsset(url: url)
        do {
            // .availableChapterLocales — языки, для которых есть метаданные глав.
            let chapterLocales = try await asset.load(.availableChapterLocales)
            guard !chapterLocales.isEmpty else { return nil }

            let locale = chapterLocales.first ?? Locale.current
            let timedGroups = try await asset.loadChapterMetadataGroups(
                withTitleLocale: locale,
                containingItemsWithCommonKeys: [.commonKeyTitle]  // Нам нужны только названия
            )
            guard !timedGroups.isEmpty else { return nil }

            return timedGroups.enumerated().map { (i, group) in
                // Название главы из метаданных, или «Глава N» если нет.
                let title = (group.items.first { $0.commonKey == .commonKeyTitle }?.stringValue) ?? "Глава \(i + 1)"
                // CMTimeGetSeconds: конвертирует CMTime (медиа-формат времени) в Double секунды.
                let duration = CMTimeGetSeconds(group.timeRange.duration)
                return AudioBook.Chapter(
                    id: UUID(),
                    title: title,
                    fileName: url.lastPathComponent,  // Все главы из одного файла
                    duration: duration,
                    index: i
                )
            }
        } catch {
            log.warning("M4B chapter extraction failed: \(error)")
            return nil  // Не удалось — вернём nil, buildChapters обработает как один файл
        }
    }

    /// Возвращает длительность аудиофайла в секундах.
    private func audioDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            return 0  // Если не можем прочитать — 0 секунд
        }
    }

    /// Ищет файл обложки (jpg/jpeg/png/webp) в папке книги.
    private func findCover(in dir: URL) -> String? {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        // Первый файл с нужным расширением — обложка.
        return items.first { imageExtensions.contains($0.pathExtension.lowercased()) }?.lastPathComponent
    }

    /// Размер файла в килобайтах (для отчёта об ошибке).
    private func fileSizeKB(_ url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = attrs?[.size] as? Int ?? 0
        return bytes / 1024
    }

    /// Ошибки импорта — понятные пользователю сообщения.
    enum ImportError: Error, LocalizedError {
        case extractionFailed(Error)  // Ошибка при распаковке ZIP
        case noAudioFiles             // В архиве нет аудиофайлов

        var errorDescription: String? {
            switch self {
            case .extractionFailed(let e): return "Ошибка распаковки: \(e.localizedDescription)"
            case .noAudioFiles:            return "В архиве нет аудиофайлов (mp3, m4a, m4b)."
            }
        }
    }
}
