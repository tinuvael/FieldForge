import Combine
import Foundation

enum MeasurementMode: String, CaseIterable {
    case automatic, manual
    var title: String { self == .automatic ? "Датчики iPhone" : "Геологический компас" }
}

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var records: [Measurement] = []
    @Published private(set) var sensorStatus = "Ожидание данных"
    @Published var errorMessage: String?
    @Published var notes = ""
    @Published private(set) var mode = MeasurementMode.automatic
    @Published var manualInput = ManualOrientationInput()
    @Published var manualNotes = ""
    @Published private(set) var savedManual: Measurement?
    let session = MeasurementSession()
    let provider: any SensorProvider
    private var store: (any MeasurementStore)?
    private var storageWritable = false
    private var measurementVisible = true
    private var foreground = false
    private var watchdog: Task<Void, Never>?
    var mock: MockSensorProvider? { provider as? MockSensorProvider }
    var displayed: Measurement? { session.displayed }
    var isHeld: Bool { session.isHeld }
    var canSave: Bool { session.canSave && storageWritable }
    var canHold: Bool { session.live?.isSavable == true }
    var manualValidationMessage: String? {
        do { _ = try manualInput.validated(); return nil }
        catch { return error.localizedDescription }
    }
    var canSaveManual: Bool { storageWritable && savedManual == nil && manualValidationMessage == nil }

    init() {
        #if targetEnvironment(simulator)
        provider = MockSensorProvider()
        #else
        provider = CoreMotionSensorProvider()
        #endif
        do {
            let fileStore = try FileMeasurementStore.applicationStore()
            #if DEBUG
            let selectedStore = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? FileMeasurementStore(url: fileStore.url.deletingLastPathComponent().appendingPathComponent("ui-testing.json"))
                : fileStore
            #else
            let selectedStore = fileStore
            #endif
            records = try selectedStore.load()
            store = selectedStore
            storageWritable = true
        } catch { errorMessage = "Не удалось открыть журнал: \(error.localizedDescription) Запись заблокирована для сохранности файла." }
        provider.onEvent = { [weak self] event in
            guard let self, self.mode == .automatic else { return }
            self.objectWillChange.send()
            switch event {
            case .sample(let sample):
                self.session.receive(sample)
                self.sensorStatus = sample.source == .simulatorMock ? "Демонстрационные данные" : "Данные Core Motion · 20 Гц"
            case .unavailable(let reason):
                self.session.invalidateLive()
                self.sensorStatus = reason
            }
        }
    }

    func setLifecycle(measurementVisible: Bool, foreground: Bool) {
        self.measurementVisible = measurementVisible
        self.foreground = foreground
        updateAcquisition()
    }
    private func updateAcquisition() {
        watchdog?.cancel(); watchdog = nil
        if mode == .automatic && measurementVisible && foreground && !isHeld {
            provider.start()
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                    guard let self else { return }
                    if let live = self.session.live,
                       Date().timeIntervalSince(live.timestamp) > 1.5 {
                        self.objectWillChange.send()
                        self.session.invalidateLive()
                        self.sensorStatus = "Данные устарели. Ожидание новых показаний."
                    }
                }
            }
        } else {
            provider.stop()
            objectWillChange.send()
            session.invalidateLive()
            if !isHeld { sensorStatus = "Датчики остановлены" }
        }
    }
    func toggleHold() {
        guard mode == .automatic else { return }
        objectWillChange.send()
        if isHeld { session.resume(); notes = "" }
        else if !session.hold() { sensorStatus = "Нельзя фиксировать: нет свежего допустимого измерения." }
        updateAcquisition()
    }
    func saveFrozen() {
        guard mode == .automatic, canSave, let record = session.record(notes: notes), let store else { return }
        do {
            let updated = ([record] + records).sorted { $0.timestamp > $1.timestamp }
            try store.save(updated)
            records = updated
            objectWillChange.send(); session.markSaved()
        } catch { errorMessage = "Не удалось сохранить: \(error.localizedDescription)" }
    }
    func setMode(_ value: MeasurementMode) {
        mode = value
        updateAcquisition()
    }
    func manualDraftChanged() { savedManual = nil }
    func saveManual() {
        guard mode == .manual, canSaveManual, let store else { return }
        do {
            let record = try manualInput.observation(notes: manualNotes)
            let updated = ([record] + records).sorted { $0.timestamp > $1.timestamp }
            try store.save(updated)
            records = updated
            savedManual = record
        } catch { errorMessage = "Не удалось сохранить: \(error.localizedDescription)" }
    }
    func newManualObservation() {
        manualInput = ManualOrientationInput(); manualNotes = ""; savedManual = nil
    }
    func delete(at offsets: IndexSet) {
        guard storageWritable, let store else { return }
        let updated = records.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        do { try store.save(updated); records = updated }
        catch { errorMessage = "Не удалось удалить: \(error.localizedDescription)" }
    }
    func updateMock(dip: Double, direction: Double, condition: MockCondition) {
        guard let mock, !isHeld else { return }
        mock.dip = dip; mock.direction = direction; mock.condition = condition; mock.emit()
    }
}
