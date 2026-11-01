// Features/Audiobooks/Services/AudiobooksViewModel.swift

import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "app.local.phoneapp", category: "AudiobooksViewModel")

@MainActor
@Observable
final class AudiobooksViewModel {
    var importProgress: Double = 0
    var isImporting = false
    var importError: String?

    let library: BookLibrary
    let player: AudioPlayer
    private let importer: ZipImporter

    init(
        library: BookLibrary,
        player: AudioPlayer,
        diagnostics: any DiagnosticRecording
    ) {
        self.library = library
        self.player = player
        self.importer = ZipImporter(diagnostics: diagnostics)
        player.prepare(library: library)
    }

    func importZip(from url: URL) {
        guard !isImporting else { return }
        isImporting = true
        importProgress = 0
        importError = nil

        Task {
            defer { isImporting = false }
            do {
                let book = try await importer.importZip(from: url) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.importProgress = progress
                    }
                }
                library.add(book)
            } catch {
                log.error("Import failed: \(error)")
                importError = error.localizedDescription
            }
        }
    }

    func deleteBook(id: UUID) {
        guard let book = library.books.first(where: { $0.id == id }) else { return }
        let dir = library.bookDirectory(for: book)
        try? FileManager.default.removeItem(at: dir)
        library.remove(id: id)
    }

    func openBook(_ book: AudioBook) {
        let progress = library.progress(for: book.id)
        player.play(
            book: book,
            chapterIndex: progress?.chapterIndex ?? 0,
            at: progress?.position ?? 0
        )
    }
}
