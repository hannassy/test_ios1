// App/BackgroundRefreshHandler.swift
//
// ═══════════════════════════════════════════════════════════
// ФОНОВОЕ ОБНОВЛЕНИЕ ГРАФИКА
// ═══════════════════════════════════════════════════════════
//
// iOS экономит батарею: приложения по умолчанию не работают в фоне.
// Но есть исключение — BGAppRefreshTask.
//
// КАК ЭТО РАБОТАЕТ:
//   1. Мы регистрируем задачу в PhoneApp.init() и планируем её (scheduleNext).
//   2. iOS сам решает, когда её запустить: обычно когда телефон на зарядке,
//      подключён к Wi-Fi и пользователь не пользуется им активно.
//   3. Система будит приложение на короткое время (несколько секунд).
//   4. Мы скачиваем свежий график и пишем снимок в App Group.
//   5. Виджет читает этот снимок и показывает актуальный статус.
//
// Если время вышло — iOS вызовет expirationHandler и убьёт задачу.
// Мы отменяем Task, чтобы не было «висящего» сетевого запроса.

import BackgroundTasks
import OSLog

// Logger — замена print() для серьёзного кода.
// subsystem + category позволяют фильтровать логи в приложении Console на Mac.
private let log = Logger(subsystem: "app.local.phoneapp", category: "BackgroundRefresh")

// enum без кейсов — просто пространство имён для статических методов.
// Создавать объект BackgroundRefreshHandler не нужно.
enum BackgroundRefreshHandler {

    // @MainActor — выполняется на главном потоке (нужно для AddressStore и WidgetSnapshotStore).
    @MainActor
    static func handleAppRefresh(task: BGAppRefreshTask) async {
        // Сразу планируем следующий запуск.
        // Делаем это в начале — на случай, если что-то упадёт дальше.
        scheduleNext()

        let store = AddressStore.shared

        // Если нет сохранённого адреса — нечего обновлять, завершаем задачу.
        guard let place = store.selectedPlace else {
            log.info("No selected place — skipping background refresh")
            task.setTaskCompleted(success: true)
            return
        }

        log.info("Background refresh for place: \(place.label)")

        // Запускаем загрузку в отдельной задаче, чтобы можно было отменить её
        // через expirationHandler если iOS решит, что время вышло.
        let refreshTask = Task {
            do {
                let client = DtekAjaxClient()
                let response = try await client.fetchSchedule(for: place)
                // Создаём снимок и сохраняем в App Group — виджет прочитает его.
                let snapshot = OutageSnapshot(place: place, response: response, fetchedAt: .now)
                try WidgetSnapshotStore.save(snapshot)
                log.info("Background refresh succeeded")
                return true
            } catch {
                log.error("Background refresh failed: \(error)")
                return false
            }
        }

        // iOS вызовет этот блок, если время задачи истекло.
        // Мы отменяем Task — она не продолжит работу после убийства процесса.
        task.expirationHandler = {
            refreshTask.cancel()
        }

        // Ждём результата и сообщаем iOS об успехе/провале.
        let success = await refreshTask.value
        task.setTaskCompleted(success: success)
    }

    // Планируем следующий фоновый запуск — не раньше чем через 3 часа.
    // iOS не гарантирует точное время: это минимальная задержка.
    // Реальный запуск может быть позже — iOS учитывает заряд, Wi-Fi, активность.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: "app.local.phoneapp.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 60 * 60) // 3 часа в секундах

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Ошибка планирования — не критично, просто логируем.
            log.error("Failed to schedule background refresh: \(error)")
        }
    }
}
