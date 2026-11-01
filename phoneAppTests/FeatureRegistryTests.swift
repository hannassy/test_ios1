// phoneAppTests/FeatureRegistryTests.swift
//
// Проверяем, что реестр содержит ровно то, что мы в него положили.
// Простые тесты — но важные: если кто-то случайно удалит функцию,
// или добавит дубликат — тест покажет это немедленно.

import Testing
@testable import phoneApp

@MainActor  // FeatureRegistry работает только на главном потоке
struct FeatureRegistryTests {

    @Test("Реестр содержит outages, audiobooks, debug")
    func registryHasExpectedFeatures() {
        let registry = FeatureRegistry.shared
        // Собираем все id в массив
        let ids = registry.features.map { $0.id }

        // Проверяем наличие каждого ожидаемого раздела
        #expect(ids.contains("outages"))
        #expect(ids.contains("audiobooks"))
        #expect(ids.contains("debug"))
    }

    @Test("Нет дублирующихся ID")
    func noDuplicateIDs() {
        let registry = FeatureRegistry.shared
        let ids = registry.features.map { $0.id }
        // Set автоматически удаляет дубликаты.
        // Если count не совпадает — есть дубликат.
        let unique = Set(ids)
        #expect(ids.count == unique.count)
    }
}
