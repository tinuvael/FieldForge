import SwiftUI

struct PlanRevisionActionRequest: Identifiable {
    let id = UUID()
    let plan: MappingPlanReference
    let action: PlanManagementChange.Action
}

struct PlanRevisionActionsView: View {
    let request: PlanRevisionActionRequest
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    @State private var target: UUID?
    @State private var replacementID: UUID?
    @State private var confirmingDelete = false
    @State private var error: String?
    private var plan: MappingPlanReference { request.plan }
    private var dependencies: [String] { mapping.workflow?.planDependencies(plan.id) ?? [] }
    private var alternatives: [MappingPlanReference] { mapping.plans(for: plan.horizonID).filter { $0.id != plan.id } }
    private var needsReplacement: Bool { mapping.activePlan(for: plan.horizonID)?.id == plan.id && !alternatives.isEmpty && request.action != .restore }
    private var restricted: Bool { !dependencies.isEmpty && (request.action == .delete || request.action == .move) }
    private var title: String {
        switch request.action {
        case .archive: return "Архивировать ревизию"
        case .restore: return "Вернуть из архива"
        case .move: return "Перенести на другой горизонт"
        case .delete: return "Удалить ревизию"
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Ревизия DXF") {
                    LabeledContent("Файл", value: plan.file?.originalFilename ?? "Нет оригинала")
                    LabeledContent("Горизонт", value: horizonName(plan.horizonID))
                    LabeledContent("Ревизия", value: plan.version)
                }
                if !dependencies.isEmpty {
                    Section("Зависимости") {
                        ForEach(dependencies, id: \.self) { Text($0) }
                        if restricted { Text("Удаление и перенос недоступны. Архивирование сохраняет наблюдения, историю и исходный DXF.") }
                    }
                }
                if request.action == .move && !restricted {
                    Section("Целевой горизонт") {
                        Picker("Перенести в", selection: $target) {
                            Text("Выберите горизонт").tag(nil as UUID?)
                            ForEach(mapping.workflow?.horizons.filter { $0.id != plan.horizonID } ?? []) {
                                Text($0.displayName).tag(Optional($0.id))
                            }
                        }.accessibilityIdentifier("planMoveHorizon")
                    }
                }
                if needsReplacement {
                    Section("Новая активная ревизия") {
                        Picker("Активная после операции", selection: $replacementID) {
                            Text("Выберите ревизию").tag(nil as UUID?)
                            ForEach(alternatives) { Text("\($0.file?.originalFilename ?? "DXF") · \($0.version)").tag(Optional($0.id)) }
                        }.accessibilityIdentifier("planReplacement")
                    }
                }
                if request.action == .delete && !restricted {
                    Text("Неиспользуемая ревизия будет удалена из списков приложения. Исходный DXF и запись об удалении сохраняются для восстановления резервных копий.")
                        .font(.caption)
                }
                if let error { Text(error).foregroundStyle(.red) }
                if restricted {
                    Button("Архивировать вместо удаления или переноса") { apply(.archive) }
                        .disabled(needsReplacement && replacementID == nil).accessibilityIdentifier("archiveUsedPlan")
                } else {
                    Button(title, role: request.action == .delete ? .destructive : nil) {
                        if request.action == .delete { confirmingDelete = true } else { apply(request.action) }
                    }.disabled((request.action == .move && target == nil) || (needsReplacement && replacementID == nil))
                        .accessibilityIdentifier("applyPlanAction")
                }
            }.disabled(mapping.isSaving).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
                .alert("Удалить неиспользуемую ревизию?", isPresented: $confirmingDelete) {
                    Button("Удалить", role: .destructive) { apply(.delete) }
                    Button("Отмена", role: .cancel) { }
                } message: { Text("\(plan.file?.originalFilename ?? "DXF") · горизонт \(horizonName(plan.horizonID)) · ревизия \(plan.version)") }
        }
    }
    private func horizonName(_ id: UUID) -> String { mapping.workflow?.journal.horizons.first { $0.id == id }?.displayName ?? "Неизвестно" }
    private func apply(_ action: PlanManagementChange.Action) {
        Task { do {
            try await mapping.managePlan(plan, action: action, targetHorizonID: action == .move ? target : nil,
                                   replacement: alternatives.first { $0.id == replacementID })
            dismiss()
        } catch { self.error = error.localizedDescription } }
    }
}
