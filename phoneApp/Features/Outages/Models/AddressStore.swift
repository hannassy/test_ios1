// Features/Outages/Models/AddressStore.swift
//
// ═══════════════════════════════════════════════════════════
// ХРАНИЛИЩЕ АДРЕСОВ
// ═══════════════════════════════════════════════════════════
//
// Хранит список сохранённых мест (дом, родители и т.д.) и
// запоминает, какое из них выбрано сейчас.
//
// PERSISTENCE (ПОСТОЯНСТВО ДАННЫХ):
//   Данные сохраняются в UserDefaults — встроенное хранилище iOS
//   для небольших настроек. Это словарь «ключ → данные», который
//   переживает перезапуск приложения.
//
//   UserDefaults не подходит для больших файлов (видео, аудио).
//   Для них используется Documents-директория (см. BookLibrary).
//   Список адресов маленький — UserDefaults здесь уместен.
//
// @Observable:
//   Макрос из фреймворка Observation (iOS 17+).
//   Когда меняется любое свойство — SwiftUI автоматически
//   перерисовывает вью, которые его читают.
//   Это замена старому @Published / ObservableObject.

import Foundation
import Observation
import SwiftUI

/// Список мест пользователя и выбранное место.
@Observable
@MainActor  // Весь класс работает на главном потоке — безопасно для SwiftUI.
final class AddressStore {

    // Синглтон: один экземпляр на всё приложение.
    static let shared = AddressStore()

    // Ключи для UserDefaults. Суффикс _v1 — версия схемы данных.
    // Если потребуется изменить формат JSON — меняем ключ на _v2
    // и пишем миграцию. Старые данные под _v1 не ломаются.
    private let key = "savedPlaces_v1"
    private let selectedKey = "selectedPlaceID_v1"

    // private(set) — читать можно снаружи, менять — только внутри класса.
    // Это защищает от случайного изменения в другом месте.
    private(set) var places: [SavedPlace] = []
    private(set) var selectedPlaceID: UUID?

    /// Вычисляемое свойство: само находит выбранное место по id.
    /// Не хранит данные, просто считает при каждом обращении.
    var selectedPlace: SavedPlace? {
        places.first(where: { $0.id == selectedPlaceID })
    }

    private init() {
        load()  // При создании загружаем сохранённые данные
    }


    // ─── Управление списком ───────────────────────────────────────────────────

    /// Добавляет новое место. Если это первое место — автоматически выбирает его.
    func add(_ place: SavedPlace) {
        places.append(place)
        if places.count == 1 {
            // Первое место всегда выбрано по умолчанию.
            selectedPlaceID = place.id
        }
        save()
    }

    /// Обновляет существующее место (например, изменили подпись).
    func update(_ place: SavedPlace) {
        // firstIndex(where:) ищет индекс первого подходящего элемента.
        guard let idx = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[idx] = place
        save()
    }

    /// Удаляет место. Если удалили выбранное — выбираем следующее доступное.
    func delete(id: UUID) {
        places.removeAll { $0.id == id }
        if selectedPlaceID == id {
            // Выбрали удалённое место — автоматически переключаемся на первое доступное.
            selectedPlaceID = places.first?.id
        }
        save()
    }

    /// Переключает выбранное место. Если id не найден в списке — игнорируем.
    func select(id: UUID) {
        guard places.contains(where: { $0.id == id }) else { return }
        selectedPlaceID = id
        // Сохраняем именно id выбранного места отдельным ключом —
        // чтобы не перекодировать весь массив при каждом переключении.
        UserDefaults.standard.set(id.uuidString, forKey: selectedKey)
    }


    // ─── Сохранение и загрузка ────────────────────────────────────────────────

    private func load() {
        // Загрузка списка мест.
        // try? — если JSON сломан, просто получим nil (пустой список).
        // В начале жизни приложения UserDefaults пуст — это нормально.
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            places = decoded
        }

        // Загрузка id выбранного места.
        if let str = UserDefaults.standard.string(forKey: selectedKey),
           let uuid = UUID(uuidString: str) {
            selectedPlaceID = uuid
        } else {
            // Нет сохранённого выбора — берём первое место (если есть).
            selectedPlaceID = places.first?.id
        }
    }

    private func save() {
        // JSONEncoder преобразует массив структур в JSON-данные.
        // guard let — если кодирование провалилось, выходим без сохранения.
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: key)

        // Сохраняем id выбранного места.
        if let id = selectedPlaceID {
            UserDefaults.standard.set(id.uuidString, forKey: selectedKey)
        }
    }
}
