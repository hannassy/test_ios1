// Features/Outages/Views/AddPlaceView.swift
// Мастер добавления нового адреса: регион → город → улица (с подсказками) → дом → подпись.

import SwiftUI

struct AddPlaceView: View {
    var viewModel: OutageViewModel
    var onDismiss: () -> Void

    @State private var label = ""
    @State private var region = DtekRegion.odesa
    @State private var city = ""
    @State private var street = ""
    @State private var house = ""
    @State private var group = ""

    @State private var isSavingHouses = false
    @State private var houseSuggestions: [String: String] = [:] // дом → группа

    @FocusState private var focusedField: Field?

    private enum Field { case label, city, street, house }

    private var canFetchHouses: Bool {
        !city.isEmpty && !street.isEmpty
    }

    private var canSave: Bool {
        !label.isEmpty && !city.isEmpty && !street.isEmpty && !house.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Дом, Родители...", text: $label)
                        .focused($focusedField, equals: .label)
                        .accessibilityLabel("Название места")
                }

                Section("Регион") {
                    Picker("Регион", selection: $region) {
                        ForEach(DtekRegion.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Адрес") {
                    TextField("Город", text: $city)
                        .focused($focusedField, equals: .city)
                        .textContentType(.addressCity)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Город")

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Улица", text: $street)
                            .focused($focusedField, equals: .street)
                            .autocorrectionDisabled()
                            .onChange(of: street) { _, new in
                                viewModel.searchStreets(region: region, city: city, query: new)
                            }
                            .accessibilityLabel("Улица")

                        if !viewModel.streetSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(viewModel.streetSuggestions.prefix(10), id: \.self) { s in
                                        Button(s) {
                                            street = s
                                            viewModel.streetSuggestions = []
                                            Task { await loadHouses() }
                                        }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }

                    if !houseSuggestions.isEmpty {
                        Picker("Дом", selection: $house) {
                            Text("Выбрать дом").tag("")
                            ForEach(houseSuggestions.keys.sorted(), id: \.self) { h in
                                Text(h).tag(h)
                            }
                        }
                        .onChange(of: house) { _, h in
                            group = houseSuggestions[h] ?? ""
                        }
                    } else {
                        TextField("Дом", text: $house)
                            .focused($focusedField, equals: .house)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Номер дома")

                        if canFetchHouses {
                            Button("Загрузить список домов") {
                                Task { await loadHouses() }
                            }
                            .font(.callout)
                        }
                    }

                    if !group.isEmpty {
                        Text("Группа: \(group)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Добавить место")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(!canSave)
                }
            }
            .overlay {
                if isSavingHouses { ProgressView() }
            }
        }
    }

    private func loadHouses() async {
        isSavingHouses = true
        defer { isSavingHouses = false }
        await viewModel.fetchHouses(region: region, city: city, street: street)
        houseSuggestions = viewModel.houseSuggestions
    }

    private func save() {
        let place = SavedPlace(
            id: UUID(),
            label: label,
            region: region,
            city: city,
            street: street,
            house: house,
            group: group
        )
        AddressStore.shared.add(place)
        viewModel.selectPlace(id: place.id)
        onDismiss()
    }
}
