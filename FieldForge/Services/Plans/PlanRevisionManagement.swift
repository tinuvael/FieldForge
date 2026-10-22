import Foundation

/// Management metadata is append-only. Original DXF bytes and the source revision identity
/// never change. Deletion retires an unused revision; originals remain for offline recovery.
struct PlanManagementChange: Codable, Equatable {
    enum Action: String, Codable { case archive, restore, move, delete }
    let action: Action
    let date: Date
    let previousHorizonID: UUID
    let horizonID: UUID
}

struct PlanElevationUnitConfirmation: Codable, Equatable {
    let units: PlanUnits
    let confirmedAt: Date
}

extension MappingPlanReference {
    /// Reconcile a leftover import intent using immutable import identity after management.
    func matchesImport(_ staged: MappingPlanReference) -> Bool {
        var initial = self
        initial.horizonID = managementHistory?.first?.previousHorizonID ?? horizonID
        initial.managementHistory = nil; initial.elevationUnitConfirmation = nil
        return initial == staged
    }
    var elevationUnitDeclaration: String { elevationUnitConfirmation == nil ? file?.unitDeclaration ?? "unknown" : "userConfirmedAtPlanReview" }
    var isDeleted: Bool { managementHistory?.contains { $0.action == .delete } == true }
    var isArchived: Bool {
        managementHistory?.last { $0.action == .archive || $0.action == .restore }?.action == .archive
    }
    var isAvailable: Bool { !isDeleted && !isArchived }
    func validateManagement() throws {
        if let confirmation = elevationUnitConfirmation {
            guard file?.units == .unknown, confirmation.confirmedAt.timeIntervalSinceReferenceDate.isFinite,
                  PlanElevationSnap.metersPerUnit(self) != nil else { throw StorageError.invalidRecord }
        }
        var horizon = managementHistory?.first?.previousHorizonID ?? horizonID
        var archived = false, deleted = false
        for event in managementHistory ?? [] {
            guard !deleted, event.date.timeIntervalSinceReferenceDate.isFinite,
                  event.previousHorizonID == horizon else { throw StorageError.invalidRecord }
            if event.action == .move {
                guard event.horizonID != horizon else { throw StorageError.invalidRecord }
                horizon = event.horizonID
            } else {
                guard event.horizonID == horizon else { throw StorageError.invalidRecord }
                switch event.action {
                case .archive: guard !archived else { throw StorageError.invalidRecord }; archived = true
                case .restore: guard archived else { throw StorageError.invalidRecord }; archived = false
                case .delete: deleted = true
                case .move: break
                }
            }
        }
        guard horizon == horizonID else { throw StorageError.invalidRecord }
    }
}

extension MappingJournal {
    func planDependencies(_ id: UUID) -> [String] {
        var result: [String] = []
        func references(_ c: MappingCoordinates?) -> Bool { c?.planID == id || c?.zPlanGeometry?.planID == id }
        if observations.contains(where: { references($0.coordinates) }) { result.append("Исходные наблюдения и происхождение координат/Z") }
        if revisions.contains(where: { references($0.snapshot.coordinates) }) { result.append("История исправлений наблюдений") }
        if plans.contains(where: { $0.id == id && $0.frameConfirmation != nil || $0.frameConfirmation?.previousPlanID == id }) {
            result.append("Подтверждённая связь систем координат ревизий")
        }
        // Qualified matching metadata can establish compatibility without an explicit edge.
        if let plan = plans.first(where: { $0.id == id && !$0.isDeleted }), plans.contains(where: {
            $0.id != id && !$0.isDeleted && PlanCoordinateCompatibility.compatible(plan, $0, plans: plans)
        }) { result.append("Совместимость координат с другими ревизиями") }
        return result
    }

    /// Storage boundary enforces immutable source metadata and append-only management history,
    /// even when callers bypass the workflow. Both old and new graph protect historical links.
    func validatePlanChanges(from previous: MappingJournal) throws {
        for old in previous.plans {
            guard let current = plans.first(where: { $0.id == old.id }) else { throw StorageError.invalidRecord }
            var source = current
            source.horizonID = old.horizonID; source.managementHistory = old.managementHistory
            source.elevationUnitConfirmation = old.elevationUnitConfirmation
            if let prior = old.elevationUnitConfirmation {
                guard current.elevationUnitConfirmation == prior else { throw StorageError.invalidRecord }
            }
            let before = old.managementHistory ?? [], after = current.managementHistory ?? []
            guard source == old, after.starts(with: before) else { throw StorageError.invalidRecord }
            if after.count == before.count {
                guard current.horizonID == old.horizonID else { throw StorageError.invalidRecord }
            } else {
                guard after[before.count].previousHorizonID == old.horizonID else { throw StorageError.invalidRecord }
            }
            for event in after.dropFirst(before.count) where event.action == .move || event.action == .delete {
                guard previous.planDependencies(old.id).isEmpty, planDependencies(old.id).isEmpty else {
                    throw MappingError.invalid("Ревизия используется наблюдениями, историей или связями координат. Доступно архивирование.")
                }
                let from = horizons.first { $0.id == event.previousHorizonID }
                let to = horizons.first { $0.id == event.horizonID }
                guard from != nil, to?.projectID == from?.projectID else { throw StorageError.invalidRecord }
            }
        }
    }
}

extension MappingWorkflow {
    mutating func confirmPlanElevationUnits(_ id: UUID, units: PlanUnits, now: Date = Date()) throws {
        guard let index = journal.plans.firstIndex(where: { $0.id == id && !$0.isDeleted }),
              journal.plans[index].elevationUnitConfirmation == nil,
              journal.plans[index].file?.units == .unknown else { throw StorageError.invalidRecord }
        var next = journal
        next.plans[index].elevationUnitConfirmation = PlanElevationUnitConfirmation(units: units, confirmedAt: now)
        try commit(next)
    }
    func planDependencies(_ id: UUID) -> [String] {
        var result = journal.planDependencies(id)
        if ([draft] + suspendedDrafts.map(\.draft)).contains(where: { $0.planID == id || $0.zPlanGeometry?.planID == id }) {
            result.append("Координаты текущего или сохранённого черновика")
        }
        return result
    }
    mutating func managePlan(_ id: UUID, action: PlanManagementChange.Action, horizonID: UUID? = nil, now: Date = Date()) throws {
        guard !draft.saving, let index = journal.plans.firstIndex(where: { $0.id == id && !$0.isDeleted }) else { throw StorageError.invalidRecord }
        let plan = journal.plans[index]
        if action == .move || action == .delete {
            let dependencies = planDependencies(id)
            guard dependencies.isEmpty else { throw MappingError.invalid(dependencies.joined(separator: ". ") + ". Ревизию можно архивировать.") }
        }
        let target = horizonID ?? plan.horizonID
        guard let sourceHorizon = journal.horizons.first(where: { $0.id == plan.horizonID }),
              journal.horizons.contains(where: { $0.id == target && $0.projectID == sourceHorizon.projectID }) else { throw StorageError.invalidRecord }
        if action == .move {
            guard !journal.plans.contains(where: { !$0.isDeleted && $0.id != id && $0.horizonID == target && PlanRevisionNumber.same($0.version, plan.version) }) else {
                throw MappingError.invalid("На целевом горизонте уже есть ревизия с таким номером. Перенос невозможен без изменения идентичности ревизии.")
            }
        }
        var next = journal
        var history = plan.managementHistory ?? []
        history.append(PlanManagementChange(action: action, date: now, previousHorizonID: plan.horizonID, horizonID: target))
        next.plans[index].managementHistory = history
        next.plans[index].horizonID = target
        try next.validatePlanChanges(from: journal)
        try commit(next)
    }
}
