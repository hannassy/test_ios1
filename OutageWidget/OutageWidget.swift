// OutageWidget/OutageWidget.swift
//
// ═══════════════════════════════════════════════════════════
// ВИДЖЕТ СТАТУСА СВЕТА
// ═══════════════════════════════════════════════════════════
//
// КАК РАБОТАЮТ ВИДЖЕТЫ В iOS:
//
//   Виджет — отдельный процесс (не часть основного приложения).
//   iOS запускает его редко и ненадёжно — нельзя рассчитывать на фоновую сеть.
//
//   Поэтому виджет не ходит в сеть сам.
//   Схема: Приложение → App Group → Виджет.
//   Приложение скачало график → записало JSON → виджет читает JSON.
//
//   TIMELINE (лента):
//   Вместо того чтобы «обновляться постоянно», виджет заранее строит
//   список момент→данные (Timeline). iOS показывает нужную запись в нужный момент.
//   Мы строим ленту по границам получасовых слотов: статус сменяется
//   ровно в 00:00, 00:30, 01:00... Экономит батарею.
//
//   TimelineProvider — протокол WidgetKit, который мы должны реализовать.
//   TimelineEntry — одна «точка» в ленте: дата + данные.

import WidgetKit
import SwiftUI


// ─── ДАННЫЕ ДЛЯ ОДНОГО МОМЕНТА ────────────────────────────────────────────────

/// Данные, которые виджет показывает в конкретный момент времени.
/// TimelineEntry требует поле date: Date — когда показывать эту запись.
struct OutageEntry: TimelineEntry {
    let date: Date             // Когда показывать эту запись (= граница слота)
    let status: SlotStatus     // Статус света в этот момент
    let placeLabel: String     // Подпись места («Дом», «Родители»)
    let nextChange: Date?      // Когда следующее переключение
    let fetchedAt: Date?       // Когда последний раз обновляли снимок
    let source: OutageStatus.StatusSource  // fact (точно) или preset (прогноз)
}


// ─── ПРОВАЙДЕР ЛЕНТЫ ──────────────────────────────────────────────────────────

struct OutageTimelineProvider: TimelineProvider {

    /// Заглушка для первого показа виджета (пока данные не загружены).
    /// iOS может показать её мгновенно — без ожидания реальных данных.
    func placeholder(in context: Context) -> OutageEntry {
        OutageEntry(
            date: .now,
            status: .on,
            placeLabel: "Дом",
            nextChange: Date().addingTimeInterval(3600),
            fetchedAt: .now,
            source: .fact
        )
    }

    /// Быстрый снимок для галереи виджетов (когда пользователь их добавляет).
    func getSnapshot(in context: Context, completion: @escaping (OutageEntry) -> Void) {
        completion(makeEntry())
    }

    /// Основной метод: строим полную ленту записей для виджета.
    func getTimeline(in context: Context, completion: @escaping (Timeline<OutageEntry>) -> Void) {
        let now = Date()

        // Нет снимка (приложение ещё не открывали) — одна запись «нет данных».
        guard let snapshot = WidgetSnapshotStore.load() else {
            let entry = OutageEntry(date: now, status: .unknown, placeLabel: "—",
                                   nextChange: nil, fetchedAt: nil, source: .noData)
            // .atEnd — попросить обновление когда закончатся записи.
            completion(Timeline(entries: [entry], policy: .atEnd))
            return
        }

        // Строим ленту по границам слотов.
        // cursor движется вперёд по времени:
        //   cursor = сейчас → nextChange → следующий nextChange → ...
        var entries: [OutageEntry] = []
        var cursor = now

        // Максимум 48 записей (24 часа при получасовых слотах).
        for _ in 0..<48 {
            let status = snapshot.currentStatus(at: cursor)
            let entry = OutageEntry(
                date: cursor,
                status: status.currentSlot,
                placeLabel: snapshot.place.label,
                nextChange: status.nextChange,
                fetchedAt: snapshot.fetchedAt,
                source: status.source
            )
            entries.append(entry)

            // Переходим к следующей точке переключения.
            // Если nextChange nil — нет больше данных, прерываем цикл.
            guard let next = status.nextChange else { break }
            cursor = next
        }

        // Просим iOS обновить виджет через 3 часа.
        // За это время приложение (при открытии или фоновой задаче) запишет новый снимок.
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(3 * 3600))
        completion(Timeline(entries: entries, policy: policy))
    }

    /// Создаёт одну запись для текущего момента.
    private func makeEntry() -> OutageEntry {
        let now = Date()
        guard let snapshot = WidgetSnapshotStore.load() else {
            return OutageEntry(date: now, status: .unknown, placeLabel: "—",
                               nextChange: nil, fetchedAt: nil, source: .noData)
        }
        let status = snapshot.currentStatus(at: now)
        return OutageEntry(
            date: now,
            status: status.currentSlot,
            placeLabel: snapshot.place.label,
            nextChange: status.nextChange,
            fetchedAt: snapshot.fetchedAt,
            source: status.source
        )
    }
}


// ─── ВНЕШНИЙ ВИД: МАЛЕНЬКИЙ ВИДЖЕТ ────────────────────────────────────────────

struct OutageWidgetSmallView: View {
    let entry: OutageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.title3)
                Spacer()
                // Название места — «Дом», «Родители» и т.д.
                Text(entry.placeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Главный текст: «Світло є» или «Немає»
            Text(entry.status.displayName)
                .font(.headline.bold())

            // До какого времени этот статус
            if let next = entry.nextChange {
                Text("до \(next.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Время последнего обновления (относительное: «2 мин назад»)
            if let fetched = entry.fetchedAt {
                Text(fetched, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        // containerBackground — фон виджета. Обязателен с iOS 17.
        .containerBackground(statusBackground, for: .widget)
    }

    private var iconName: String {
        switch entry.status {
        case .on:      return "bolt.fill"
        case .off:     return "bolt.slash.fill"
        case .maybe:   return "bolt.badge.clock"
        case .unknown: return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch entry.status {
        case .on:      return .yellow
        case .off:     return .gray
        case .maybe:   return .orange
        case .unknown: return .secondary
        }
    }

    private var statusBackground: Color {
        switch entry.status {
        case .on:      return Color(.systemBackground)  // Нейтральный
        case .off:     return Color(.systemGray6)        // Чуть серый — нет света
        case .maybe:   return Color.orange.opacity(0.1)  // Тёплый — неопределённость
        case .unknown: return Color(.systemBackground)
        }
    }
}


// ─── ВНЕШНИЙ ВИД: СРЕДНИЙ ВИДЖЕТ ──────────────────────────────────────────────

struct OutageWidgetMediumView: View {
    let entry: OutageEntry

    var body: some View {
        HStack(spacing: 16) {
            // Левая часть: место, иконка, статус, время
            VStack(alignment: .leading, spacing: 6) {
                Label(entry.placeLabel, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: iconName)
                    .font(.system(size: 36))
                    .foregroundStyle(iconColor)

                Text(entry.status.displayName)
                    .font(.title3.bold())

                if let next = entry.nextChange {
                    Text("до \(next.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Правая часть: источник данных + время обновления
            VStack(alignment: .trailing, spacing: 4) {
                // Предупреждение если данные прогнозные, а не подтверждённые
                if entry.source == .preset {
                    Text("Прогноз")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let fetched = entry.fetchedAt {
                    VStack(alignment: .trailing) {
                        Text("Обновлено")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(fetched, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
        .containerBackground(Color(.systemBackground), for: .widget)
    }

    private var iconName: String {
        switch entry.status {
        case .on:      return "bolt.fill"
        case .off:     return "bolt.slash.fill"
        case .maybe:   return "bolt.badge.clock"
        case .unknown: return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch entry.status {
        case .on:      return .yellow
        case .off:     return .gray
        case .maybe:   return .orange
        case .unknown: return .secondary
        }
    }
}


// ─── ОПИСАНИЕ ВИДЖЕТА ─────────────────────────────────────────────────────────

/// Конфигурация виджета — название, описание, поддерживаемые размеры.
struct OutageWidget: Widget {
    // kind — уникальная строка-идентификатор виджета.
    // Нужна если в приложении несколько виджетов (у нас один).
    let kind = "OutageWidget"

    var body: some WidgetConfiguration {
        // StaticConfiguration — виджет без настройки пользователем.
        // (Есть ещё IntentConfiguration — с настройкой через Siri Shortcuts.)
        StaticConfiguration(kind: kind, provider: OutageTimelineProvider()) { entry in
            OutageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Статус света")
        .description("Показывает, есть ли сейчас електроенергія.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Выбирает нужный вью в зависимости от размера виджета.
struct OutageWidgetEntryView: View {
    // widgetFamily — текущий размер виджета (small, medium...).
    // iOS автоматически передаёт это значение через Environment.
    @Environment(\.widgetFamily) var family
    let entry: OutageEntry

    var body: some View {
        switch family {
        case .systemSmall:
            OutageWidgetSmallView(entry: entry)
        case .systemMedium:
            OutageWidgetMediumView(entry: entry)
        default:
            OutageWidgetSmallView(entry: entry)
        }
    }
}

// @main в расширении работает так же, как в приложении.
// WidgetBundle объединяет все виджеты (у нас один).
@main
struct OutageWidgetBundle: WidgetBundle {
    var body: some Widget {
        OutageWidget()
    }
}
