// Features/Audiobooks/Views/AudiobooksRootView.swift

import SwiftUI
import UniformTypeIdentifiers

struct AudiobooksRootView: View {
    @State private var viewModel: AudiobooksViewModel
    @State private var showImporter = false
    @State private var showPlayer = false
    @State private var selectedBook: AudioBook?

    init(viewModel: AudiobooksViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.library.books.isEmpty && !viewModel.isImporting {
                    emptyLibraryView
                } else {
                    bookListView
                }
            }
            .navigationTitle("Аудиокниги")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Добавить", systemImage: "square.and.arrow.down") {
                        showImporter = true
                    }
                    .accessibilityLabel("Импортировать ZIP с книгой")
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.importZip(from: url)
                }
            }
            .sheet(isPresented: $showPlayer) {
                if let book = selectedBook {
                    PlayerView(book: book, player: viewModel.player, library: viewModel.library)
                }
            }
        }
    }

    // MARK: Subviews

    private var emptyLibraryView: some View {
        ContentUnavailableView(
            "Нет аудиокниг",
            systemImage: "headphones",
            description: Text("Нажми кнопку ↓ вверху, чтобы добавить ZIP с книгой")
        )
    }

    private var bookListView: some View {
        List {
            if viewModel.isImporting {
                Section("Импорт...") {
                    ProgressView(value: viewModel.importProgress)
                        .accessibilityLabel("Идёт распаковка архива")
                }
            }

            if let err = viewModel.importError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            ForEach(viewModel.library.books) { book in
                BookRowView(book: book, progress: viewModel.library.progress(for: book.id))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedBook = book
                        viewModel.openBook(book)
                        showPlayer = true
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.deleteBook(id: book.id)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
            }
        }
    }
}
