// Features/Audiobooks/Views/PlayerView.swift
// Экран плеера: управление воспроизведением, список глав, скорость.

import SwiftUI

struct PlayerView: View {
    let book: AudioBook
    @State var player: AudioPlayer
    @State var library: BookLibrary
    @State private var showChapters = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Обложка
                BookCoverView(book: book, size: 200)
                    .shadow(radius: 8)

                // Название книги и глава
                VStack(spacing: 6) {
                    Text(book.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)

                    if player.currentChapterIndex < book.chapters.count {
                        Text(book.chapters[player.currentChapterIndex].title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)

                // Прогресс
                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ), in: 0...(max(player.duration, 1)))
                    .accessibilityLabel("Позиция воспроизведения")

                    HStack {
                        Text(formatTime(player.currentTime))
                        Spacer()
                        Text(formatTime(player.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Кнопки управления
                HStack(spacing: 32) {
                    Button { player.previousChapter() } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Предыдущая глава")

                    Button { player.skipBackward() } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    }
                    .accessibilityLabel("Назад 15 секунд")

                    Button {
                        player.isPlaying ? player.pause() : player.resume()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }
                    .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")

                    Button { player.skipForward() } label: {
                        Image(systemName: "goforward.30")
                            .font(.title2)
                    }
                    .accessibilityLabel("Вперёд 30 секунд")

                    Button { player.nextChapter() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Следующая глава")
                }
                .foregroundStyle(.primary)

                // Скорость и главы
                HStack(spacing: 16) {
                    // Скорость
                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0] as [Float], id: \.self) { r in
                            Button("\(r.formatted(.number.precision(.fractionLength(2))))x") {
                                player.setRate(r)
                            }
                        }
                    } label: {
                        Label("\(player.rate.formatted(.number.precision(.fractionLength(2))))x", systemImage: "speedometer")
                            .font(.callout)
                    }
                    .accessibilityLabel("Скорость воспроизведения")

                    Spacer()

                    // Главы
                    Button {
                        showChapters = true
                    } label: {
                        Label("Главы", systemImage: "list.bullet")
                            .font(.callout)
                    }
                    .accessibilityLabel("Список глав")
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Плеер")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showChapters) {
                ChapterListView(book: book, player: player)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Список глав

struct ChapterListView: View {
    let book: AudioBook
    @State var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(book.chapters) { chapter in
                Button {
                    player.play(book: book, chapterIndex: chapter.index, at: 0)
                    dismiss()
                } label: {
                    HStack {
                        if chapter.index == player.currentChapterIndex {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.accentColor)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading) {
                            Text(chapter.title)
                                .foregroundStyle(.primary)
                            Text(formatTime(chapter.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel("Глава: \(chapter.title), длительность \(formatTime(chapter.duration))")
                .accessibilityAddTraits(chapter.index == player.currentChapterIndex ? .isSelected : [])
            }
            .navigationTitle("Главы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}
