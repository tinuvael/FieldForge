import SwiftUI

/// Representatives are explicit interpretations; accepted readings remain separate originals.
struct MappingJointSetsSection: View {
    @EnvironmentObject private var mapping: MappingModel
    let edit: (MappingGeologyEditorRequest) -> Void
    private var sets: [JointSetDraft] { mapping.workflow?.draft.jointSets ?? [] }
    var body: some View {
        Section("Трещиноватость и тектоника") {
            Text("Системы трещин").font(.subheadline).foregroundStyle(.secondary)
            ForEach(sets) { set in
                HStack {
                    Button { if let workflow = mapping.workflow { edit(.joint(workflow.editorRequest(set))) } } label: {
                        HStack {
                            Text(set.identifier.rawValue).font(.headline)
                            if let value = try? set.representative.validated() {
                                Text("\(AngleText.format(value.orientation.dipDirection, azimuth: true)) / \(AngleText.format(value.orientation.dipAngle))")
                                    .monospacedDigit()
                            } else { Text("Заполнить ориентацию") }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("editJointSet-\(set.identifier.rawValue)")
                    Button(role: .destructive) {
                        mapping.perform { $0.draft.jointSets.removeAll { $0.id == set.id } }
                    } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Удалить \(set.identifier.rawValue) из черновика")
                }.buttonStyle(.borderless)
            }
            Button("Добавить систему", systemImage: "plus") {
                guard let identifier = JointSetIdentifier.allCases.first(where: { candidate in !sets.contains { $0.identifier == candidate } }) else { return }
                if let workflow = mapping.workflow { edit(.joint(workflow.editorRequest(JointSetDraft(identifier: identifier)))) }
            }.disabled(sets.count >= 5).accessibilityIdentifier("addJointSet")
            Text("Тектоника").font(.subheadline).foregroundStyle(.secondary)
            ForEach(mapping.workflow?.draft.tectonicStructures ?? []) { structure in
                HStack {
                    Button { if let workflow = mapping.workflow { edit(.tectonic(workflow.editorRequest(structure))) } } label: {
                        HStack { Text(structure.type.title); Spacer(); Image(systemName: "pencil") }.frame(minHeight: 44)
                    }.accessibilityIdentifier("editTectonic-\(structure.id.uuidString)")
                    Button(role: .destructive) {
                        mapping.perform { $0.draft.tectonicStructures.removeAll { $0.id == structure.id } }
                    } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Удалить структуру из черновика")
                }.buttonStyle(.borderless)
            }
            Button("Добавить структуру", systemImage: "plus") {
                if let workflow = mapping.workflow { edit(.tectonic(workflow.editorRequest(TectonicStructureDraft()))) }
            }
                .accessibilityIdentifier("addTectonicStructure")
        }
    }
}

enum MappingGeologyEditorRequest: Identifiable {
    case joint(MappingEditorRequest<JointSetDraft>)
    case tectonic(MappingEditorRequest<TectonicStructureDraft>)
    var id: UUID {
        switch self { case .joint(let request): return request.id; case .tectonic(let request): return request.id }
    }
}

/// Presented by MappingView, outside the lazy Form/Section host lifetime.
struct MappingGeologyCaptureSheet: View {
    let request: MappingGeologyEditorRequest
    @EnvironmentObject private var mapping: MappingModel
    var body: some View {
        switch request {
        case .tectonic(let request):
            TectonicCaptureSheet(initial: request.initial) { updated in
                guard mapping.workflow != nil else { throw StorageError.writesBlocked }
                try mapping.workflow!.acceptTectonic(updated, request: request)
            }.id(request.id)
        case .joint(let request):
            JointSetCaptureSheet(initial: request.initial, measurements: request.measurements) { updated, originals in
                guard mapping.workflow != nil else { throw StorageError.writesBlocked }
                try mapping.workflow!.acceptJointSet(updated, originals: originals, request: request)
            }.id(request.id)
        }
    }
}

private struct JointSetCaptureSheet: View {
    let initial: JointSetDraft
    let measurements: [Measurement]
    let apply: (JointSetDraft?, [Measurement]) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JointSetDraft
    @State private var originals: [Measurement] = []
    @State private var acceptedRepresentative: ManualOrientationInput?
    @State private var measuring = false
    @State private var discard = false
    @State private var error: String?
    @State private var originalNotice: String?
    @FocusState private var focused: Bool
    @FocusState private var orientationFocus: OrientationField?
    private enum OrientationField { case direction, dip }
    init(initial: JointSetDraft, measurements: [Measurement], apply: @escaping (JointSetDraft?, [Measurement]) throws -> Void) {
        self.initial = initial; self.measurements = measurements; self.apply = apply
        _draft = State(initialValue: initial)
    }
    private var sensorRepresentative: ManualOrientationInput? {
        if let acceptedRepresentative { return acceptedRepresentative }
        return (measurements + originals).reversed().compactMap { reading -> ManualOrientationInput? in
            guard draft.measurementIDs.contains(reading.id), reading.source == .iPhoneSensor || reading.source == .simulatorMock else { return nil }
            return try? JointRepresentativeInput.make(from: reading)
        }.first
    }
    private var manuallyModified: Bool {
        sensorRepresentative.map { $0 != draft.representative } ?? false
    }
    private var changed: Bool { draft != initial || !originals.isEmpty }
    private var valid: Bool { (try? draft.record(now: Date())) != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section("Представительная ориентация") {
                    TextField("Азимут падения, °", text: orientationText(\.dipDirectionText, field: .direction))
                        .keyboardType(.decimalPad).focused($orientationFocus, equals: .direction).accessibilityIdentifier("geologyDirection")
                    TextField("Угол падения, °", text: orientationText(\.dipAngleText, field: .dip))
                        .keyboardType(.decimalPad).focused($orientationFocus, equals: .dip).accessibilityIdentifier("geologyDip")
                    Button("Замерить iPhone", systemImage: "iphone.radiowaves.left.and.right") { focused = false; orientationFocus = nil; measuring = true }
                    Picker("Север", selection: $draft.representative.reference) {
                        ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
                    }
                    if Double(draft.representative.dipAngleText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) == 90 || draft.representative.usesConventionalDipSide {
                        Toggle("Условная сторона вертикальной плоскости", isOn: $draft.representative.usesConventionalDipSide)
                    }
                    if manuallyModified {
                        Label("Представительная ориентация изменена вручную", systemImage: "pencil")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("jointManuallyModified")
                    }
                    if let message = validationMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                }
                DisclosureGroup("Полевые характеристики") {
                    TextField("Расстояние между трещинами, м", text: $draft.spacing).focused($focused).keyboardType(.decimalPad)
                    TextField("Протяжённость, м", text: $draft.persistence).focused($focused).keyboardType(.decimalPad)
                    TextField("Раскрытие, мм", text: $draft.aperture).focused($focused).keyboardType(.decimalPad)
                    TextField("Шероховатость", text: $draft.roughness).focused($focused)
                    TextField("Заполнитель", text: $draft.infill).focused($focused)
                    TextField("Примечания", text: $draft.notes, axis: .vertical).focused($focused)
                }
                if let originalNotice {
                    Section {
                        Text(originalNotice).font(.caption)
                        Button("Сохранить отдельные замеры") {
                            do { try apply(nil, originals); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Система \(draft.identifier.rawValue)").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(changed)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { focused = false; orientationFocus = nil; if changed { discard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Принять") {
                        focused = false; orientationFocus = nil
                        do {
                            var updated = draft, evidence = originals
                            if sensorRepresentative == nil && updated.representative != initial.representative {
                                let manual = try updated.representative.observation()
                                evidence.append(manual); updated.measurementIDs.append(manual.id)
                            }
                            try apply(updated, evidence); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(!valid)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false; orientationFocus = nil } }
            }
            .confirmationDialog("Отбросить изменения системы?", isPresented: $discard, titleVisibility: .visible) {
                Button("Отбросить", role: .destructive) { dismiss() }
            }
            .fullScreenCover(isPresented: $measuring) {
                MappingMeasurementSheet(automatic: true, addTitle: "Принять как \(draft.identifier.rawValue)",
                    representativeIssue: { JointRepresentativeInput.issue(for: $0) },
                    onKeepOriginal: { reading in
                        try stageOriginal(reading)
                        originalNotice = "Исходный замер принят отдельно; ориентация системы не изменена."
                    }) { reading in
                        let representative = try JointRepresentativeInput.make(from: reading)
                        try stageOriginal(reading)
                        draft.representative = representative
                        acceptedRepresentative = representative
                        draft.measurementIDs.append(reading.id)
                        originalNotice = nil
                    }
            }
        }
    }
    private func orientationText(_ key: WritableKeyPath<ManualOrientationInput, String>, field: OrientationField) -> Binding<String> {
        Binding(get: {
            let text = draft.representative[keyPath: key]
            guard orientationFocus != field || sensorRepresentative?[keyPath: key] == text,
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return text }
            return EngineeringDisplay.orientationInput(value)
        }, set: { draft.representative[keyPath: key] = $0 })
    }
    private func stageOriginal(_ reading: Measurement) throws {
        guard reading.isSavable, !(measurements + originals).contains(where: { $0.id == reading.id }) else {
            throw MappingError.invalid("Замер неполный или уже добавлен.")
        }
        originals.append(reading)
    }
    private var validationMessage: String? {
        do { _ = try draft.record(now: Date()); return nil } catch { return error.localizedDescription }
    }
}

private struct TectonicCaptureSheet: View {
    let initial: TectonicStructureDraft
    let apply: (TectonicStructureDraft) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TectonicStructureDraft
    @State private var discard = false
    @State private var error: String?
    init(initial: TectonicStructureDraft, apply: @escaping (TectonicStructureDraft) throws -> Void) {
        self.initial = initial; self.apply = apply; _draft = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            TectonicStructureEditor(draft: $draft)
                .interactiveDismissDisabled(draft != initial)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { if draft != initial { discard = true } else { dismiss() } }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Принять") {
                            do { try apply(draft); dismiss() } catch { self.error = error.localizedDescription }
                        }.disabled((try? draft.record()) == nil)
                    }
                }
                .confirmationDialog("Отбросить изменения структуры?", isPresented: $discard, titleVisibility: .visible) {
                    Button("Отбросить", role: .destructive) { dismiss() }
                }
                .alert("Структура не добавлена", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("Понятно", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
    }
}
