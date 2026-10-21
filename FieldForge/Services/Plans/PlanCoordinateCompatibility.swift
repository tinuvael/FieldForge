import Foundation

/// An explicit same-frame declaration made while importing a new immutable revision.
struct PlanFrameConfirmation: Codable, Equatable {
    let previousPlanID: UUID
    let confirmedAt: Date
}

/// No transforms: equality of qualified metadata, or a validated explicit declaration.
/// A horizon UUID implies one project; names are never used as frame identifiers.
enum PlanCoordinateCompatibility {
    private static func known(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["", "unknown", "неизвестно", "неизвестна", "не указано", "?", "local", "локальная", "местная"].contains(value) ? nil : value
    }
    private static func noConflict(_ a: MappingPlanReference, _ b: MappingPlanReference) -> Bool {
        guard a.horizonID == b.horizonID, let x = a.file, let y = b.file,
              x.units != .unknown, x.units == y.units else { return false }
        for (left, right) in [(x.crs, y.crs), (x.axes, y.axes)] {
            if let left = known(left), let right = known(right), left != right { return false }
        }
        return true
    }
    private static func linked(_ a: MappingPlanReference, _ b: MappingPlanReference) -> Bool {
        guard noConflict(a, b), let x = a.file, let y = b.file else { return false }
        if a.frameConfirmation?.previousPlanID == b.id || b.frameConfirmation?.previousPlanID == a.id { return true }
        guard let crs = known(x.crs), let axes = known(x.axes) else { return false }
        return crs == known(y.crs) && axes == known(y.axes)
    }
    private static func component(_ plan: MappingPlanReference, plans: [MappingPlanReference]) -> [MappingPlanReference] {
        var found = [plan], ids: Set<UUID> = [plan.id], index = 0
        while index < found.count {
            for candidate in plans where !ids.contains(candidate.id) && linked(found[index], candidate) {
                ids.insert(candidate.id); found.append(candidate)
            }
            index += 1
        }
        return found
    }
    static func compatible(_ a: MappingPlanReference, _ b: MappingPlanReference, plans: [MappingPlanReference]) -> Bool {
        guard plans.contains(a), plans.contains(b) else { return false }
        if a.id == b.id { return true } // Preserve original-plan display, including unknown units.
        let group = component(a, plans: plans)
        return group.contains(b) && group.allSatisfy { left in group.allSatisfy { noConflict(left, $0) } }
    }
    static func validate(_ plans: [MappingPlanReference]) throws {
        for plan in plans {
            if let confirmation = plan.frameConfirmation {
                guard confirmation.confirmedAt.timeIntervalSinceReferenceDate.isFinite,
                      let previous = plans.first(where: { $0.id == confirmation.previousPlanID }),
                      previous.id != plan.id, noConflict(plan, previous) else {
                    throw MappingError.invalid("Ревизии имеют несовместимые единицы, СК или оси. Проверьте источник координат.")
                }
                var seen: Set<UUID> = [plan.id], current = previous
                while true {
                    guard seen.insert(current.id).inserted else { throw StorageError.invalidRecord }
                    guard let id = current.frameConfirmation?.previousPlanID else { break }
                    guard let next = plans.first(where: { $0.id == id }) else { throw StorageError.invalidRecord }
                    current = next
                }
                let group = component(plan, plans: plans)
                guard group.allSatisfy({ a in group.allSatisfy { noConflict(a, $0) } }) else {
                    throw MappingError.invalid("Подтверждение противоречит системе координат прежних ревизий.")
                }
            }
        }
    }
}

struct MappingPlanSelectionRequest: Identifiable {
    let id = UUID()
    let draftID: UUID
    let context: MappingContext
    let plan: MappingPlanReference
}

extension MappingWorkflow {
    func planSelectionRequest(_ plan: MappingPlanReference) throws -> MappingPlanSelectionRequest {
        guard !draft.saving, pendingContext == nil, plans.contains(plan), plan.file != nil else { throw StorageError.invalidRecord }
        return MappingPlanSelectionRequest(draftID: draft.id, context: context, plan: plan)
    }
    mutating func selectPlanPoint(_ point: PlanPoint, request: MappingPlanSelectionRequest) throws {
        guard draft.id == request.draftID, context == request.context, pendingContext == nil else {
            throw MappingError.invalid("Черновик точки изменился. Выберите место заново.")
        }
        try selectPlanPoint(point, planID: request.plan.id)
    }
}
