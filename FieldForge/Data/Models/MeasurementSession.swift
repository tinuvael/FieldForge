import Foundation

/// Presentation-independent HOLD state. The entire observation is frozen, including diagnostics.
@MainActor final class MeasurementSession {
    private(set) var live: Measurement?
    private(set) var frozen: Measurement?
    private(set) var hasSavedFrozen = false
    var displayed: Measurement? { frozen ?? live }
    var isHeld: Bool { frozen != nil }
    var canSave: Bool { frozen?.isSavable == true && !hasSavedFrozen }

    func receive(_ sample: SensorSample) { live = Measurement.process(sample) }
    func invalidateLive() { live = nil }
    @discardableResult func hold(now: Date = Date()) -> Bool {
        guard frozen == nil, let live, live.isSavable,
              (0...1.5).contains(now.timeIntervalSince(live.timestamp)) else { return false }
        frozen = live
        hasSavedFrozen = false
        return true
    }
    func resume() { frozen = nil; live = nil; hasSavedFrozen = false }
    func record(notes: String) -> Measurement? {
        guard canSave, var value = frozen else { return nil }
        value.notes = notes
        return value
    }
    func markSaved() { if canSave { hasSavedFrozen = true } }
}
