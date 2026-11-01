// phoneAppTests/AddressStoreTests.swift
//
// Тесты логики управления сохранёнными адресами.
// Проверяем: автовыбор, переключение, удаление.

import Testing
import Foundation
@testable import phoneApp

// @MainActor — AddressStore работает только на главном потоке
@MainActor
struct AddressStoreTests {

    // Вспомогательная функция: создаёт тестовый адрес с заданными параметрами
    private func place(label: String, region: DtekRegion = .odesa) -> SavedPlace {
        SavedPlace(id: UUID(), label: label, region: region,
                   city: "Тест", street: "вул. Т", house: "1", group: "G")
    }

    // Очищает все места перед тестом, чтобы тесты не мешали друг другу.
    // AddressStore.shared — синглтон, его состояние сохраняется между тестами.
    private func clearStore() {
        let store = AddressStore.shared
        store.places.forEach { store.delete(id: $0.id) }
    }


    @Test("Первое добавленное место становится выбранным")
    func firstAddedIsSelected() {
        clearStore()
        let store = AddressStore.shared

        let p = place(label: "Дом")
        store.add(p)

        // После добавления первого места — оно должно быть автоматически выбрано
        #expect(store.selectedPlaceID == p.id)
    }

    @Test("Переключение места меняет selectedPlaceID")
    func switchPlace() {
        clearStore()
        let store = AddressStore.shared

        let p1 = place(label: "Дом", region: .odesa)
        let p2 = place(label: "Родители", region: .dnipro)
        store.add(p1)
        store.add(p2)

        // После добавления двух мест — выбрано первое
        store.select(id: p2.id)

        #expect(store.selectedPlaceID == p2.id)
        #expect(store.selectedPlace?.label == "Родители")
    }

    @Test("Удаление выбранного места переключает на следующее")
    func deleteSelectedSwitches() {
        clearStore()
        let store = AddressStore.shared

        let p1 = place(label: "Дом")
        let p2 = place(label: "Офис")
        store.add(p1)
        store.add(p2)
        store.select(id: p1.id)  // Выбираем первое

        store.delete(id: p1.id)  // Удаляем выбранное

        // После удаления — должно автоматически переключиться на p2
        #expect(store.selectedPlaceID == p2.id)
    }
}
