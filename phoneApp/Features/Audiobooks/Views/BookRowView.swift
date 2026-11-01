// Features/Audiobooks/Views/BookRowView.swift

import SwiftUI

struct BookRowView: View {
    let book: AudioBook
    let progress: BookProgress?

    private var progressFraction: Double {
        guard let p = progress else { return 0 }
        let totalDuration = book.chapters.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else { return 0 }
        let played = book.chapters.prefix(p.chapterIndex).reduce(0.0) { $0 + $1.duration } + p.position
        return min(played / totalDuration, 1.0)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Обложка или заглушка
            BookCoverView(book: book, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityLabel(book.title)

                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("\(book.chapters.count) гл.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if progressFraction > 0 {
                    ProgressView(value: progressFraction)
                        .tint(.accentColor)
                        .accessibilityLabel("Прослушано \(Int(progressFraction * 100))%")
                }
            }
        }
        .padding(.vertical, 4)
    }
}
