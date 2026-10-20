import SwiftUI

/// Representatives are explicit interpretations; accepted readings remain separate originals.
struct MappingJointSetsSection: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var editing: JointSetDraft?
    private var sets: [JointSetDraft] { mapping.workflow?.draft.jointSets ?? [] }
    var body: some View {
        Section("Системы трещин") {
            ForEach(sets) { set in
                HStack {
                    Button { editing = set } label: {
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
                editing = JointSetDraft(identifier: identifier)
            }.disabled(sets.count >= 5).accessibilityIdentifier("addJointSet")
        }
        .sheet(item: $editing) { set in
            JointSetCaptureSheet(initial: set, measurements: mapping.workflow?.draft.measurements ?? []) { updated, originals in
                guard let workflow = mapping.workflow else { throw StorageError.writesBlocked }
                var next = workflow.draft
                for reading in originals { try next.addMeasurement(reading) }
                next.jointSets.removeAll { $0.id == updated.id }
                next.jointSets.append(updated)
                next.jointSets.sort { $0.identifier.rawValue < $1.identifier.rawValue }
                guard next.jointSets.count <= 5 else { throw StorageError.invalidRecord }
                mapping.workflow!.draft = next
            }
        }
    }
}

private struct JointSetCaptureSheet: View {
    let initial: JointSetDraft
    let measurements: [Measurement]
    let apply: (JointSetDraft, [Measurement]) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JointSetDraft
    @State private var originals: [Measurement] = []
    @State private var acceptedRepresentative: ManualOrientationInput?
    @State private var measuring = false
    @State private var discard = false
    @State private var error: String?
    @FocusState private var focused: Bool
    init(initial: JointSetDraft, measurements: [Measurement], apply: @escaping (JointSetDraft, [Measurement]) throws -> Void) {
        self.initial = initial; self.measurements = measurements; self.apply = apply
        _draft = State(initialValue: initial)
    }
    private var changed: Bool { draft != initial || !originals.isEmpty }
    private var valid: Bool { (try? draft.record(now: Date())) != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section("Представительная ориентация") {
                    TextField("Азимут падения, °", text: $draft.representative.dipDirectionText)
                        .keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("geologyDirection")
                    TextField("Угол падения, °", text: $draft.representative.dipAngleText)
                        .keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("geologyDip")
                    Button("Замерить iPhone", systemImage: "iphone.radiowaves.left.and.right") { focused = false; measuring = true }
                    Picker("Север", selection: $draft.representative.reference) {
                        ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
                    }
                    if Double(draft.representative.dipAngleText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) == 90 || draft.representative.usesConventionalDipSide {
                        Toggle("Условная сторона вертикальной плоскости", isOn: $draft.representative.usesConventionalDipSide)
                    }
                    if let message = validationMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                }
                DisclosureGroup("Дополнительно") {
                    Text("J1–J5 — явные интерпретации. Исходные замеры сохраняются отдельно; усреднение и пересчёт севера не выполняются.").font(.caption)
                    TextField("Расстояние между трещинами, м", text: $draft.spacing).focused($focused).keyboardType(.decimalPad)
                    TextField("Протяжённость, м", text: $draft.persistence).focused($focused).keyboardType(.decimalPad)
                    TextField("Раскрытие, мм", text: $draft.aperture).focused($focused).keyboardType(.decimalPad)
                    TextField("Шероховатость", text: $draft.roughness).focused($focused)
                    TextField("Заполнитель", text: $draft.infill).focused($focused)
                    TextField("Примечания", text: $draft.notes, axis: .vertical).focused($focused)
                    TextField("Автор интерпретации", text: $draft.author).focused($focused)
                    ForEach(measurements + originals) { reading in
                        Toggle(isOn: Binding(get: { draft.measurementIDs.contains(reading.id) }, set: { on in
                            draft.measurementIDs.removeAll { $0 == reading.id }
                            if on { draft.measurementIDs.append(reading.id) }
                        })) { MeasurementSummary(reading: reading) }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(draft.identifier.rawValue).navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(changed)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { focused = false; if changed { discard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Принять \(draft.identifier.rawValue)") {
                        focused = false
                        do {
                            var updated = draft, evidence = originals
                            if updated.representative != initial.representative && updated.representative != acceptedRepresentative {
                                let manual = try updated.representative.observation()
                                evidence.append(manual); updated.measurementIDs.append(manual.id)
                            }
                            try apply(updated, evidence); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(!valid)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false } }
            }
            .confirmationDialog("Отбросить изменения системы?", isPresented: $discard, titleVisibility: .visible) {
                Button("Отбросить", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $measuring) {
                MappingMeasurementSheet(automatic: true, addTitle: "Принять как \(draft.identifier.rawValue)") { reading in
                    guard GeographicReference.manualChoices.contains(reading.reference) else {
                        throw MappingError.invalid("Этот замер не имеет поддерживаемого вида севера для представительной системы. Сохраните его как исходный замер через «Дополнительно»; DEMO и недоступный север не преобразуются.")
                    }
                    var representative = ManualOrientationInput()
                    representative.dipAngleText = reading.orientation.dipAngle.map(ElevationInput.text) ?? ""
                    representative.dipDirectionText = reading.orientation.dipDirection.map(ElevationInput.text) ?? ""
                    representative.reference = reading.reference
                    representative.usesConventionalDipSide = reading.directionMeaning == .conventionalDipSide
                    _ = try representative.validated()
                    originals.append(reading)
                    draft.representative = representative
                    acceptedRepresentative = representative
                    draft.measurementIDs.append(reading.id)
                }
            }
        }
    }
    private var validationMessage: String? {
        do { _ = try draft.record(now: Date()); return nil } catch { return error.localizedDescription }
    }
}
