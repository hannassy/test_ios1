// Features/Audiobooks/AudiobooksFeature.swift
//
// ═══════════════════════════════════════════════════════════
// ТОЧКА ВХОДА ФУНКЦИИ «АУДИОКНИГИ»
// ═══════════════════════════════════════════════════════════
//
// Создаёт зависимости модуля: библиотеку, плеер, ViewModel.
// Всё внутри папки Audiobooks/ — остальной код не знает об этих объектах.

import SwiftUI

@MainActor
final class AudiobooksFeature: AppFeature {
    let id: FeatureID = "audiobooks"
    let title = "Аудиокниги"
    let symbolName = "headphones"

    // ViewModel хранит все зависимости аудио-модуля.
    private let viewModel: AudiobooksViewModel

    init(diagnosticLog: any DiagnosticRecording) {
        // BookLibrary и AudioPlayer создаются здесь — один раз на всё время жизни функции.
        // Они живут, пока жив AudiobooksFeature (то есть всё время работы приложения).
        let library = BookLibrary()
        let player  = AudioPlayer()

        self.viewModel = AudiobooksViewModel(
            library: library,
            player:  player,
            diagnostics: diagnosticLog  // Для записи ошибок в журнал Debug
        )
    }

    func makeRootView() -> AnyView {
        AnyView(AudiobooksRootView(viewModel: viewModel))
    }
}
