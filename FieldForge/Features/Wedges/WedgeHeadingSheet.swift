import SwiftUI

@MainActor private final class WedgeHeadingModel: ObservableObject {
    @Published private(set) var sample: SensorSample?
    @Published private(set) var heading: Double?
    @Published private(set) var message = "Подготовка магнитного направления…"
    private let provider = CoreMotionSensorProvider()
    private var timer: Timer?
    private var active = false
    private var generation = UUID()

    func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        generation = UUID()
        let request = generation
        if value {
            provider.onEvent = { [weak self] event in
                guard let self, self.active else { return }
                switch event {
                case .sample(let value): self.sample = value; self.refresh()
                case .unavailable(let reason): self.sample = nil; self.heading = nil; self.message = reason
                }
            }
            provider.start()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.active, self.generation == request else { return }
                    self.refresh()
                }
            }
        } else {
            provider.stop(); timer?.invalidate(); timer = nil; sample = nil; heading = nil
            message = "Замер остановлен. Ручной ввод доступен в форме."
        }
    }
    private func refresh() {
        heading = sample.flatMap { WedgePlaneGeometry.axisHeading(sample: $0, now: Date()) }
        message = heading == nil
            ? "Нет пригодного направления. Держите телефон спокойно, верхним краем вперёд, экраном вверх. Проверьте магнитные помехи или введите азимут вручную."
            : "Магнитный север · калибровка высокая. Локальные помехи всё ещё возможны."
    }
    func capture() -> WedgeAxisCapture? {
        guard active, let sample, let value = WedgePlaneGeometry.axisHeading(sample: sample, now: Date()) else { return nil }
        return WedgeAxisCapture(azimuth: value, sample: sample)
    }
    isolated deinit { timer?.invalidate() }
}

struct WedgeHeadingSheet: View {
    let onCapture: (WedgeAxisCapture) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = WedgeHeadingModel()
    var body: some View {
        NavigationStack {
            Form {
                Section("Направление оси") {
                    Text("Держите iPhone в портретной ориентации, почти горизонтально, экраном вверх. Направьте верхний край вдоль выработки в сторону увеличения пикетажа.")
                    Text(EngineeringDisplay.angle(model.heading, azimuth: true))
                        .font(.largeTitle.monospacedDigit()).frame(maxWidth: .infinity)
                    Text(model.message).font(.subheadline)
                    if let sample = model.sample {
                        DisclosureGroup("Технические сведения") {
                            Text("Магнитное поле: \(EngineeringDisplay.number(sample.magneticField.length, decimals: 1)) мкТл")
                        }.font(.caption)
                    }
                    Button("Принять направление") {
                        if let capture = model.capture() { onCapture(capture); dismiss() }
                    }.disabled(model.heading == nil)
                }
                Section {
                    Text("Это направление верхнего края телефона, а не падение плоскости. Точность не проверена на приборе; геодезическая привязка и позиционирование не выполняются. Результат временный.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Замерить ось").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
        .onAppear { model.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onDisappear { model.setActive(false) }
    }
}
