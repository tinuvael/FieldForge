import Combine
import Foundation

enum MeasurementMode: String, CaseIterable {
    case automatic, manual
    var title: String { self == .automatic ? "Датчики iPhone" : "Геологический компас" }
}

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var records: [Measurement] = []
    var sensorStatus: String { acquisition.status }
    @Published var errorMessage: String?
    @Published var notes = ""
    @Published private(set) var mode = MeasurementMode.automatic
    @Published var manualInput = ManualOrientationInput()
    @Published var manualNotes = ""
    @Published private(set) var savedManual: Measurement?
    let acquisition: MeasurementAcquisition
    var session: MeasurementSession { acquisition.session }
    var provider: any SensorProvider { acquisition.provider }
    private var store: (any MeasurementStore)?
    private var storageWritable = false
    var measurementScreenVisible = false
    var mock: MockSensorProvider? { provider as? MockSensorProvider }
    var displayed: Measurement? { session.displayed }
    var isHeld: Bool { session.isHeld }
    var canSave: Bool { session.canSave && storageWritable }
    var canHold: Bool { session.canHold() }
    var manualValidationMessage: String? {
        do { _ = try manualInput.validated(); return nil }
        catch { return error.localizedDescription }
    }
    var canSaveManual: Bool { storageWritable && savedManual == nil && manualValidationMessage == nil }

    init(captureOnly: Bool = false) {
        #if targetEnvironment(simulator)
        acquisition = MeasurementAcquisition(provider: MockSensorProvider())
        #else
        acquisition = MeasurementAcquisition(provider: CoreMotionSensorProvider())
        #endif
        if captureOnly {
            acquisition.onChange = { [weak self] in self?.objectWillChange.send() }
            return
        }
        do {
            let fileStore = try FileMeasurementStore.applicationStore()
            #if DEBUG && targetEnvironment(simulator)
            let namespace = ProcessInfo.processInfo.environment["FIELD_FORGE_TEST_RUN_ID"].flatMap(UUID.init(uuidString:)).map { "-" + $0.uuidString } ?? ""
            #else
            let namespace = ""
            #endif
            #if DEBUG
            let selectedStore = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? FileMeasurementStore(url: fileStore.url.deletingLastPathComponent().appendingPathComponent("ui-testing\(namespace).json"))
                : fileStore
            #else
            let selectedStore = fileStore
            #endif
            records = try selectedStore.load()
            store = selectedStore
            storageWritable = true
        } catch { errorMessage = "Не удалось открыть журнал: \(error.localizedDescription) Запись заблокирована для сохранности файла." }
        acquisition.onChange = { [weak self] in self?.objectWillChange.send() }
    }

    func measurementScreenVisibilityChanged(_ visible: Bool) {
        measurementScreenVisible = visible
        acquisition.setVisible(visible)
    }
    func setLifecycle(measurementVisible: Bool, foreground: Bool) {
        acquisition.setLifecycle(visible: measurementVisible, foreground: foreground)
    }
    func toggleHold() {
        guard mode == .automatic else { return }
        if isHeld { acquisition.reset(); notes = "" }
        else { acquisition.hold() }
    }
    // Mapping capture never calls the standalone store or depends on its writable state.
    func beginMappingCapture() {
        acquisition.setVisible(false)
        acquisition.reset(); notes = ""
        setMode(.automatic)
        measurementScreenVisibilityChanged(true)
    }
    func endMappingCapture() {
        measurementScreenVisibilityChanged(false)
        acquisition.reset(); notes = ""
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
        acquisition.setAutomatic(value == .automatic)
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
