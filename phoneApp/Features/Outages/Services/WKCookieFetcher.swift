// Features/Outages/Services/WKCookieFetcher.swift
//
// ═══════════════════════════════════════════════════════════
// ПОЛУЧЕНИЕ WAF-COOKIES ЧЕРЕЗ ВСТРОЕННЫЙ БРАУЗЕР
// ═══════════════════════════════════════════════════════════
//
// ЗАЧЕМ ЭТО НУЖНО:
//   Сайт ДТЭК защищён системой Incapsula (WAF — Web Application Firewall).
//   При первом обращении WAF проверяет, реальный ли это браузер:
//   запускает JavaScript, проверяет заголовки, выдаёт cookies.
//   URLSession не может пройти эту проверку — он не выполняет JS.
//
//   WKWebView — полноценный браузер WebKit внутри приложения.
//   Он проходит проверку, получает нужные cookies.
//   Мы перехватываем эти cookies и используем в дальнейших URLSession-запросах.
//
// ЖИЗНЕННЫЙ ЦИКЛ WKWebView:
//   1. Создаём WKWebView с нулевым размером (.zero) — невидимый.
//   2. Грузим страницу графика.
//   3. Получаем cookies из httpCookieStore.
//   4. WKWebView уничтожается (выходит из области видимости) — память освобождается.
//   Держать WKWebView в памяти постоянно не нужно.
//
// withCheckedThrowingContinuation — мост между колбэком и async/await.
//   WKWebView работает через делегат (oldschool колбэки).
//   Continuation позволяет «заморозить» async-функцию до вызова resume().

import WebKit
import OSLog

private let log = Logger(subsystem: "app.local.phoneapp", category: "WKCookieFetcher")

// @MainActor — WKWebView требует главного потока iOS.
// Все UI-компоненты в iOS работают только на Main Thread.
@MainActor
enum WKCookieFetcher {

    /// Синхронная точка входа для вызова из DtekAjaxClient через MainActor.run.
    /// Возвращает пустой массив — реальная логика в fetchCookiesAsync.
    ///
    /// Почему не async: actor вызывает через MainActor.run { ... },
    /// который может выполнить только синхронный код.
    /// fetchCookiesAsync вызывается там, где есть полный async-контекст.
    static func fetchCookies(from url: URL) throws -> [HTTPCookie] {
        // placeholder: реальный WKWebView запускается через fetchCookiesAsync.
        // Здесь возвращаем пустой массив — DtekAjaxClient обработает это
        // как «нет cookies» и использует fetchCookiesAsync напрямую при необходимости.
        return []
    }

    /// Async-версия: создаёт WKWebView, загружает страницу, возвращает cookies.
    static func fetchCookiesAsync(from url: URL) async throws -> [HTTPCookie] {
        // withCheckedThrowingContinuation «замораживает» функцию здесь.
        // Управление вернётся когда вызовем continuation.resume().
        try await withCheckedThrowingContinuation { continuation in
            let config = WKWebViewConfiguration()
            // frame: .zero — невидимый WebView, нам не нужен интерфейс.
            let webView = WKWebView(frame: .zero, configuration: config)
            // Флаг-защита от двойного resume (continuation нельзя вызывать дважды).
            var didResume = false

            // Создаём делегат, который вызывается когда страница загружена.
            let delegate = NavigationDelegate {
                guard !didResume else { return }
                didResume = true
                // Запрашиваем все cookies из хранилища WKWebView.
                // getAllCookies — асинхронный, результат приходит в колбэке.
                config.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    log.info("WKWebView fetched \(cookies.count) cookies from \(url.host ?? "")")
                    // «Размораживаем» нашу async-функцию с результатом.
                    continuation.resume(returning: cookies)
                }
            } onError: { error in
                guard !didResume else { return }
                didResume = true
                log.error("WKWebView failed: \(error)")
                continuation.resume(throwing: DtekError.cookiesFailed)
            }

            // Назначаем делегат. WKWebView вызовет его методы при загрузке.
            webView.navigationDelegate = delegate

            // Начинаем загрузку страницы.
            let request = URLRequest(url: url)
            webView.load(request)

            // ВАЖНО: без этого ARC (Automatic Reference Counting) уничтожит
            // delegate сразу после выхода из этого блока, и колбэк никогда не вызовется.
            // objc_setAssociatedObject «прикрепляет» delegate к webView —
            // пока жив webView, жив и delegate.
            objc_setAssociatedObject(webView, &AssociatedKeys.delegate, delegate, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // Ключ для objc_setAssociatedObject. var (не let) потому что нужен указатель.
    private enum AssociatedKeys {
        static var delegate = "delegate"
    }
}


// ─── НАВИГАЦИОННЫЙ ДЕЛЕГАТ ────────────────────────────────────────────────────

/// NSObject + WKNavigationDelegate — старый Objective-C способ подписки на события.
/// WKWebView требует именно такой делегат (это API Apple, мы не выбираем).
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void      // Вызывается когда страница загружена
    private let onError: (Error) -> Void  // Вызывается при ошибке загрузки

    init(onFinish: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        self.onFinish = onFinish
        self.onError = onError
    }

    // Страница успешно загружена.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }

    // Ошибка во время загрузки (например, потеря соединения).
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError(error)
    }

    // Ошибка до начала загрузки (например, неверный URL).
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError(error)
    }
}
