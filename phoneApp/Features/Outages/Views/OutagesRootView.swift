// Features/Outages/Views/OutagesRootView.swift
// Корневой вью функции «Світло» со своим NavigationStack.

import SwiftUI

struct OutagesRootView: View {
    @State private var viewModel: OutageViewModel
    @State private var showAddPlace = false
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: OutageViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.snapshot == nil && !viewModel.isLoading {
                    noAddressView
                } else {
                    outageContentView
                }
            }
            .navigationTitle("Світло")
            .toolbar { toolbarContent }
            .refreshable { viewModel.refresh() }
            .sheet(isPresented: $showAddPlace) {
                AddPlaceView(viewModel: viewModel, onDismiss: { showAddPlace = false })
            }
            .onChange(of: scenePhase) { _, new in
                if new == .active { viewModel.refresh() }
            }
            .task { viewModel.refresh() }
        }
    }

    // MARK: Subviews

    private var noAddressView: some View {
        ContentUnavailableView(
            "Адрес не добавлен",
            systemImage: "mappin.slash",
            description: Text("Добавь адрес, чтобы видеть график отключений")
        )
        .overlay(alignment: .bottom) {
            Button("Добавить адрес") { showAddPlace = true }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }

    private var outageContentView: some View {
        List {
            // Переключатель мест
            if AddressStore.shared.places.count > 1 {
                Section("Место") {
                    PlaceSwitcherView(store: AddressStore.shared, viewModel: viewModel)
                }
            }

            // Текущий статус
            if let status = viewModel.currentStatus {
                Section {
                    CurrentStatusView(status: status)
                }
            }

            // Сообщение об ошибке
            if let err = viewModel.error {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Ошибка: \(err)")
                }
            }

            // График на день
            if let snap = viewModel.snapshot {
                Section("Сегодня") {
                    DayScheduleView(snapshot: snap)
                }
                Section("Неделя (прогноз)") {
                    WeekScheduleView(snapshot: snap)
                }
                Section {
                    Text("Обновлено: \(snap.fetchedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if viewModel.isLoading { ProgressView() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Добавить место", systemImage: "plus") {
                showAddPlace = true
            }
            .accessibilityLabel("Добавить адрес")
        }
    }
}
