// Features/Outages/Views/PlaceSwitcherView.swift
// Переключатель между сохранёнными местами.

import SwiftUI

struct PlaceSwitcherView: View {
    @Bindable var store: AddressStore
    var viewModel: OutageViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(store.places) { place in
                    Button {
                        viewModel.selectPlace(id: place.id)
                    } label: {
                        Text(place.label)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                place.id == store.selectedPlaceID
                                    ? Color.accentColor
                                    : Color(.systemGray5)
                            )
                            .foregroundStyle(
                                place.id == store.selectedPlaceID ? .white : .primary
                            )
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel("Выбрать \(place.label)")
                    .accessibilityAddTraits(place.id == store.selectedPlaceID ? .isSelected : [])
                }
            }
        }
    }
}
