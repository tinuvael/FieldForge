import Foundation

/// One provider and HOLD session shared by standalone and mapping presentation.
/// Visibility/foreground changes stop acquisition and discard only unfrozen samples.
@MainActor final class MeasurementAcquisition {
    let provider: any SensorProvider
    let session = MeasurementSession()
    var onChange: (() -> Void)?
    private(set) var status = "Ожидание данных"
    private var visible = false
    private var foreground = false
    private var automatic = true
    private var acquiring = false
    private var watchdog: Task<Void, Never>?

    init(provider: any SensorProvider) {
        self.provider = provider
        provider.onEvent = { [weak self] event in
            guard let self, self.acquiring else { return }
            switch event {
            case .sample(let sample):
                self.session.receive(sample)
                self.status = sample.source == .simulatorMock ? "Демонстрационные данные" : "Данные Core Motion · 20 Гц"
            case .unavailable(let reason):
                self.session.invalidateLive(); self.status = reason
            }
            self.onChange?()
        }
    }
    func setLifecycle(visible: Bool, foreground: Bool) {
        self.visible = visible; self.foreground = foreground; update()
    }
    func setAutomatic(_ value: Bool) { automatic = value; update() }
    func setVisible(_ value: Bool) { visible = value; update() }
    func reset() { session.resume(); update() }
    func hold(now: Date = Date()) {
        if !session.hold(now: now) { status = "Нельзя фиксировать: нет свежего допустимого измерения." }
        update()
    }
    func expire(now: Date = Date()) {
        if let live = session.live, !(0...1.5).contains(now.timeIntervalSince(live.timestamp)) {
            session.invalidateLive(); status = "Данные устарели. Ожидание новых показаний."; onChange?()
        }
    }
    private func update() {
        watchdog?.cancel(); watchdog = nil
        acquiring = automatic && visible && foreground && !session.isHeld
        if acquiring {
            provider.start()
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                    self?.expire()
                }
            }
        } else {
            provider.stop(); session.invalidateLive()
            if !session.isHeld { status = "Датчики остановлены" }
        }
        onChange?()
    }
}
