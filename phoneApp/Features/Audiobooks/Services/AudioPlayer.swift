// Features/Audiobooks/Services/AudioPlayer.swift
//
// ═══════════════════════════════════════════════════════════
// ПЛЕЕР АУДИОКНИГ
// ═══════════════════════════════════════════════════════════
//
// Использует три системных фреймворка:
//
// AVFoundation — воспроизведение аудио:
//   AVPlayer        — основной плеер. Умеет играть файлы, стримы.
//   AVPlayerItem    — «что играть»: конкретный файл или URL.
//   AVAudioSession  — управление аудиосессией (фон, Bluetooth, громкость).
//
// MediaPlayer — интеграция с iOS:
//   MPRemoteCommandCenter — кнопки на экране блокировки и в Control Center.
//   MPNowPlayingInfoCenter — обложка + название + прогресс на экране блокировки.
//
// АУДИОСЕССИЯ:
//   iOS не позволяет всем приложениям играть звук одновременно.
//   AVAudioSession управляет тем, кто сейчас играет.
//   Категория .playback — играем даже в фоне, даже с отключённым звуком телефона.
//   Режим .spokenAudio — оптимизация для разговорного аудио (книги, подкасты).
//   Мы включаем сессию при старте воспроизведения и выключаем при остановке.

import AVFoundation
import MediaPlayer
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "app.local.phoneapp", category: "AudioPlayer")

@MainActor
@Observable
final class AudioPlayer {

    // ─── Состояние (читается View) ────────────────────────────────────────────
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0   // Позиция в текущей главе (секунды)
    private(set) var duration: TimeInterval = 0      // Длительность текущей главы
    private(set) var currentBook: AudioBook?         // Текущая книга
    private(set) var currentChapterIndex: Int = 0   // Индекс текущей главы
    private(set) var rate: Float = 1.0               // Скорость воспроизведения

    // ─── Внутренние объекты ───────────────────────────────────────────────────
    private var player: AVPlayer?          // Основной плеер
    private var playerItem: AVPlayerItem?  // Текущий элемент воспроизведения
    private var timeObserver: Any?         // Наблюдатель за позицией (тип Any — требование API)
    private var library: BookLibrary?      // Для сохранения прогресса

    private let supportedRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]


    // ─── Публичный API ────────────────────────────────────────────────────────

    /// Подключает библиотеку для сохранения прогресса.
    /// Вызывается один раз после создания.
    func prepare(library: BookLibrary) {
        self.library = library
    }

    /// Начинает воспроизведение книги с указанной главы и позиции.
    func play(book: AudioBook, chapterIndex: Int = 0, at position: TimeInterval = 0) {
        currentBook = book
        currentChapterIndex = chapterIndex
        loadChapter(index: chapterIndex, startAt: position)
    }

    /// Возобновляет воспроизведение (после паузы).
    func resume() { player?.rate = rate }

    /// Ставит на паузу.
    func pause() { player?.pause(); isPlaying = false }

    /// Перематывает к конкретной позиции.
    /// toleranceBefore: .zero — точная перемотка (чуть медленнее, но точно).
    func seek(to time: TimeInterval) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Прыжок вперёд на 30 секунд. min() защищает от выхода за конец.
    func skipForward(by seconds: TimeInterval = 30) {
        seek(to: min(currentTime + seconds, duration))
    }

    /// Прыжок назад на 15 секунд. max() защищает от отрицательного времени.
    func skipBackward(by seconds: TimeInterval = 15) {
        seek(to: max(currentTime - seconds, 0))
    }

    /// Меняет скорость воспроизведения. Если сейчас играет — применяет сразу.
    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying { player?.rate = newRate }
    }

    /// Переходит к следующей главе.
    func nextChapter() {
        guard let book = currentBook else { return }
        let next = currentChapterIndex + 1
        guard next < book.chapters.count else { return }
        currentChapterIndex = next
        loadChapter(index: next, startAt: 0)
    }

    /// Переходит к предыдущей главе. Если первая — перематывает в начало.
    func previousChapter() {
        guard currentChapterIndex > 0 else { seek(to: 0); return }
        currentChapterIndex -= 1
        loadChapter(index: currentChapterIndex, startAt: 0)
    }


    // ─── Загрузка главы ───────────────────────────────────────────────────────

    private func loadChapter(index: Int, startAt position: TimeInterval) {
        guard let book = currentBook else { return }
        guard index < book.chapters.count else { return }

        let chapter = book.chapters[index]
        let dir = BookLibrary.audioBooksDirectory.appending(path: book.folderName)
        let fileURL = dir.appending(path: chapter.fileName)

        // Останавливаем предыдущее воспроизведение и очищаем ресурсы.
        tearDown()
        // Включаем аудиосессию перед созданием плеера.
        activateAudioSession()

        // AVPlayerItem — «что играть». AVPlayer — «кто играет».
        let item = AVPlayerItem(url: fileURL)
        playerItem = item
        let p = AVPlayer(playerItem: item)
        p.rate = 0  // Не стартуем сразу — сначала сделаем seek к нужной позиции
        player = p

        // ── Периодический наблюдатель позиции ──────────────────────────────
        // Вызывается примерно каждые 0.5 секунды.
        // Обновляем currentTime — SwiftUI обновит слайдер и экран блокировки.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // [weak self] — слабая ссылка, чтобы не создавать цикл удержания (retain cycle).
            // Без weak self: player держит observer, observer держит self,
            // self держит player — никто не освободится.
            guard let self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            self.duration = CMTimeGetSeconds(item.duration)
            self.saveProgress()      // Сохраняем позицию
            self.updateNowPlaying()  // Обновляем экран блокировки
        }

        // ── Уведомление о конце файла ───────────────────────────────────────
        // NotificationCenter — система событий iOS. Как EventEmitter в JS.
        // AVPlayerItemDidPlayToEndTime: «файл воспроизведён до конца».
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),  // #selector — указатель на метод
            name: .AVPlayerItemDidPlayToEndTime,
            object: item  // Слушаем только этот конкретный item
        )

        // ── Seek + старт воспроизведения ────────────────────────────────────
        // Перематываем к нужной позиции, потом стартуем.
        let cm = CMTime(seconds: position, preferredTimescale: 600)
        p.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            p.rate = self.rate  // Стартуем с нужной скоростью
            self.isPlaying = true
            self.setupRemoteControls()  // Включаем кнопки на экране блокировки
            self.updateNowPlaying()
        }
    }

    /// Вызывается когда файл воспроизведён до конца.
    @objc private func playerDidFinish() {
        guard let book = currentBook else { return }
        let next = currentChapterIndex + 1
        if next < book.chapters.count {
            // Есть следующая глава — переходим к ней.
            currentChapterIndex = next
            loadChapter(index: next, startAt: 0)
        } else {
            // Последняя глава завершена — останавливаемся.
            isPlaying = false
            deactivateAudioSession()  // Освобождаем аудиосессию
        }
    }

    /// Останавливает плеер и освобождает все ресурсы.
    private func tearDown() {
        // Снимаем наблюдатель позиции — иначе будет вызываться после смены файла.
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        player?.pause()
        player = nil
        playerItem = nil
    }


    // ─── Аудиосессия ──────────────────────────────────────────────────────────

    /// Активирует аудиосессию перед началом воспроизведения.
    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback — главная категория для воспроизведения. Работает в фоне.
            // .spokenAudio — оптимизация: iOS снижает громкость других звуков при паузе.
            // .allowBluetooth / .allowBluetoothA2DP — работает с беспроводными наушниками.
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            log.error("Audio session activation failed: \(error)")
        }
    }

    /// Деактивирует аудиосессию когда плеер остановлен.
    /// .notifyOthersOnDeactivation — сообщает другим приложениям (Spotify, музыка),
    /// что они могут снова играть.
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.warning("Audio session deactivation failed: \(error)")
        }
    }


    // ─── Сохранение прогресса ─────────────────────────────────────────────────

    private func saveProgress() {
        guard let book = currentBook else { return }
        let progress = BookProgress(
            bookID: book.id,
            chapterIndex: currentChapterIndex,
            position: currentTime,
            updatedAt: .now
        )
        library?.saveProgress(progress)
    }


    // ─── Управление с экрана блокировки ──────────────────────────────────────

    /// Подключает обработчики кнопок Control Center и экрана блокировки.
    private func setupRemoteControls() {
        let center = MPRemoteCommandCenter.shared()

        // addTarget возвращает обработчик. .success = «команда выполнена».
        center.playCommand.addTarget  { [weak self] _ in self?.resume();         return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause();          return .success }

        // Прыжки — стандартные 30 сек вперёд, 15 назад (как в подкаст-плеерах).
        center.skipForwardCommand.preferredIntervals  = [30]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget  { [weak self] _ in self?.skipForward();  return .success }
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.skipBackward(); return .success }

        // Навигация по главам (как кнопки ⏮ ⏭).
        center.nextTrackCommand.addTarget     { [weak self] _ in self?.nextChapter();     return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.previousChapter(); return .success }
    }

    /// Обновляет информацию на экране блокировки: название, прогресс, обложку.
    private func updateNowPlaying() {
        guard let book = currentBook else { return }
        let chapter = book.chapters[currentChapterIndex]

        var info: [String: Any] = [
            MPMediaItemPropertyTitle:               chapter.title,
            MPMediaItemPropertyArtist:              book.author.isEmpty ? book.title : book.author,
            MPMediaItemPropertyAlbumTitle:          book.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration:    duration,
            // При паузе rate = 0 — прогресс-бар замирает.
            MPNowPlayingInfoPropertyPlaybackRate:   isPlaying ? Double(rate) : 0.0,
        ]

        // Обложка: загружаем в уменьшенном размере (scale=2 = @2x).
        // Полноразмерное изображение (напр. 1000×1000) не нужно для миниатюры на блокировке.
        if let coverName = book.coverFileName {
            let dir = BookLibrary.audioBooksDirectory.appending(path: book.folderName)
            let coverURL = dir.appending(path: coverName)
            if let data = try? Data(contentsOf: coverURL),
               let image = UIImage(data: data, scale: 2.0) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                info[MPMediaItemPropertyArtwork] = artwork
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
