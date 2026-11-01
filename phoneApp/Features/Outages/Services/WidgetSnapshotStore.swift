// Features/Outages/Services/WidgetSnapshotStore.swift
//
// ═══════════════════════════════════════════════════════════
// ХРАНИЛИЩЕ СНИМКА ДЛЯ ВИДЖЕТА
// ═══════════════════════════════════════════════════════════
//
// КАК ПРИЛОЖЕНИЕ И ВИДЖЕТ ОБМЕНИВАЮТСЯ ДАННЫМИ:
//
//   Виджет — это отдельный процесс (не приложение).
//   Процессы в iOS изолированы: каждый видит только свои файлы.
//
//   Исключение — App Group: специальная папка, доступная нескольким
//   приложениям/расширениям одного разработчика.
//   В project.yml мы объявили группу «group.app.local.phoneapp».
//   Оба таргета (приложение и виджет) имеют к ней доступ.
//
//   Схема:
//     Приложение        App Group          Виджет
//     скачало  ──►  пишет snapshot.json ◄── читает ──► экран
//     график
//
//   Виджет сам по сети не ходит — только читает файл.
//   Это важно: iOS редко и ненадёжно даёт виджету доступ к сети.

import Foundation

enum WidgetSnapshotStore {

    // Имя файла в папке App Group.
    // Суффикс _v1 — версия схемы. При изменении формата меняем на _v2.
    private static let filename = "outage_snapshot_v1.json"

    /// URL файла снимка в App Group. Может быть nil, если App Group
    /// не настроена (например, в симуляторе без правильных entitlements).
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.local.phoneapp")?
            .appending(path: filename)
    }

    /// Сохраняет снимок в App Group. Виджет прочитает его при следующем обновлении.
    static func save(_ snapshot: OutageSnapshot) throws {
        guard let url = fileURL else {
            throw SnapshotError.appGroupUnavailable
        }
        let data = try JSONEncoder().encode(snapshot)
        // .atomic: записываем во временный файл, потом атомарно переименовываем.
        // Если приложение упадёт в середине записи — файл не повредится.
        try data.write(to: url, options: .atomic)
    }

    /// Загружает последний сохранённый снимок.
    /// Возвращает nil если файла нет или он повреждён.
    static func load() -> OutageSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(OutageSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    /// Ошибки хранилища.
    enum SnapshotError: Error, LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            // Если видим эту ошибку — нужно проверить Signing & Capabilities в Xcode.
            "App Group недоступен. Проверь настройки приложения."
        }
    }
}
