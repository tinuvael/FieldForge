import SwiftUI

extension MappingCorrectionDraft: Identifiable { var id: UUID { baseline.id } }

struct MappingCorrectionEditor: View {
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MappingCorrectionDraft
    @State private var error: String?
    @State private var discard = false
    @State private var showPlans = false
    @FocusState private var focused: Bool
    @State private var coordinateFocus: String?
    init(draft: MappingCorrectionDraft) { _draft = State(initialValue: draft) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Исправление сохранённого наблюдения") {
                    Text("Проект, горизонт, выработка и исходные замеры сохраняются. Изменения создадут новую версию той же точки.").font(.caption)
                    TextField("Причина исправления · обязательно", text: $draft.reason, axis: .vertical)
                        .focused($focused).accessibilityIdentifier("correctionReason")
                    TextField("Автор исправления · необязательно", text: $draft.author)
                        .focused($focused).accessibilityIdentifier("correctionAuthor")
                }
                Section("Пикет и полевая дата") {
                    TextField("Пикет", text: $draft.fields.picket).keyboardType(.numbersAndPunctuation).focused($focused).accessibilityIdentifier("correctionPicket")
                    if draft.fields.picketConvention == .legacyMeters {
                        Text("Прежний формат: метры или ПК км+метры. Значение в метрах сохраняется.").font(.caption)
                    } else if let confirmation = FieldPicketInput.confirmation(draft.fields.picket) {
                        Text(confirmation).font(.caption)
                    }
                    TextField("Начало / направление пикетажа", text: $draft.fields.chainageOriginAndDirection).focused($focused)
                    DatePicker("Дата наблюдения", selection: Binding(get: { draft.fields.observedAtOverride ?? draft.baseline.observedAt },
                        set: { draft.fields.observedAtOverride = $0 }))
                        .environment(\.timeZone, TimeZone(identifier: draft.fields.timeZoneID) ?? .gmt)
                    TextField("Часовой пояс наблюдения (IANA)", text: $draft.fields.timeZoneID).focused($focused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Исходная полевая дата: \(MappingDateText.format(draft.baseline)). Время исправления запишется отдельно при сохранении.").font(.caption)
                }
                Section {
                    MappingIntervalForm(start: $draft.fields.startPicket, end: $draft.fields.endPicket,
                                        position: $draft.fields.observationPosition, focus: $focused,
                                        startConvention: draft.fields.startPicketConvention, endConvention: draft.fields.endPicketConvention)
                }
                Section("Координаты") {
                    MappingCoordinateField(title: "X", text: $draft.fields.x, identifier: "correctionX", focus: $coordinateFocus)
                    MappingCoordinateField(title: "Y", text: $draft.fields.y, identifier: "correctionY", focus: $coordinateFocus)
                    MappingCoordinateField(title: "Z", text: $draft.fields.z, identifier: "correctionZ", focus: $coordinateFocus,
                        source: (try? ElevationInput.meters(draft.fields.z)) != nil ? (draft.fields.zPlanGeometry?.sourceLabel ?? draft.fields.zOrigin?.fieldLabel) : nil,
                        sourceDetails: draft.fields.zPlanGeometry?.sourceDetails)
                    Button("Выбрать на плане") { focused = false; coordinateFocus = nil; showPlans = true }.accessibilityIdentifier("correctionSelectPlan")
                    DisclosureGroup("СК, оси и происхождение") {
                        TextField("СК", text: $draft.fields.crs).focused($focused).disabled(draft.fields.planID != nil)
                        TextField("Оси", text: $draft.fields.axes).focused($focused).disabled(draft.fields.planID != nil)
                        TextField("Происхождение координат", text: $draft.fields.coordinateProvenance, axis: .vertical)
                            .focused($focused).disabled(draft.fields.planID != nil)
                        Text("XY: \(MappingCoordinateText.xyUnit(draft.fields.xyUnits)); источник: \(xySourceTitle)").font(.caption)
                        if let id = draft.fields.planID { Text("План: \(id.uuidString)").font(.caption).textSelection(.enabled) }
                    }
                }
                Section("Исходные замеры · только просмотр") {
                    Text("Добавление, удаление, правка и перенос исходных замеров при исправлении недоступны. Ссылки J1–J5 могут указывать только на исходные замеры этой точки.").font(.caption)
                    ForEach(draft.initial.measurements) { reading in
                        NavigationLink { MeasurementDetailView(record: reading) } label: { MeasurementSummary(reading: reading) }
                    }
                }
                RockLithologyField(rock: $draft.fields.rock, projectID: draft.baseline.projectID)
                MappingGeologyForm(sets: $draft.fields.jointSets, structures: $draft.fields.tectonicStructures,
                    measurements: draft.initial.measurements, addSet: { draft.fields.addJointSet() }, spacingRQD: draft.fields.spacingRQD)
                MappingRatingsForm(q: $draft.fields.bartonQ, rmr: $draft.fields.rmr89, gsi: $draft.fields.gsi, focus: $focused)
                Section("Примечания") {
                    TextField("Примечания", text: $draft.fields.notes, axis: .vertical).focused($focused).accessibilityIdentifier("correctionNotes")
                }
                Section {
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("correctionError") }
                    Button("Сохранить исправление") { save() }.buttonStyle(.borderedProminent).accessibilityIdentifier("saveMappingCorrection")
                }
            }.disabled(mapping.isSaving).navigationTitle("Исправление наблюдения").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { if draft.hasChanges { discard = true } else { dismiss() } }.accessibilityIdentifier("cancelMappingCorrection")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false; coordinateFocus = nil } }
                }
                .interactiveDismissDisabled(draft.hasChanges)
                .alert("Отбросить несохранённое исправление?", isPresented: $discard) {
                    Button("Отбросить исправление", role: .destructive) { dismiss() }
                    Button("Продолжить редактирование", role: .cancel) {}
                }
                .sheet(isPresented: $showPlans) {
                    NavigationStack {
                        List {
                            Text("Только сохранённые версии планов исходного горизонта. XY сохраняются в единицах выбранного чертежа без пересчёта; Z отдельно, в метрах.").font(.caption)
                            ForEach(mapping.workflow?.journal.plans.filter { $0.horizonID == draft.baseline.horizonID && $0.file != nil && $0.isAvailable } ?? []) { plan in
                                NavigationLink {
                                    HorizonPlanLoader(plan: plan, selecting: true, onSelection: { showPlans = false }, onPointSelection: { point, plan, elevation in
                                        try draft.fields.selectPlanPoint(point, plan: plan, elevation: elevation)
                                    })
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(plan.file?.originalFilename ?? "DXF")
                                        Text("Версия: \(plan.version)").font(.subheadline)
                                        Text(plan.file?.units.label ?? "Неизвестно").font(.caption)
                                    }
                                }.accessibilityIdentifier("correctionPlan-\(plan.id.uuidString)")
                            }
                        }.navigationTitle("План исправления")
                            .toolbar { Button("Закрыть") { showPlans = false } }
                    }
                }
        }
    }
    private var xySourceTitle: String {
        switch draft.fields.xySource {
        case "plan": return "выбор на плане"
        case "manualInPlan": return "ручной ввод в системе плана"
        default: return "ручной ввод"
        }
    }
    private func save() {
        focused = false
        let snapshot = draft
        Task {
            do {
                _ = try await mapping.persist { try $0.saveCorrection(snapshot) }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct MappingRevisionHistory: View {
    @EnvironmentObject private var mapping: MappingModel
    let observationID: UUID
    var body: some View {
        List {
            if let original = mapping.workflow?.journal.observations.first(where: { $0.id == observationID }) {
                Section("Версия 1 · исходное наблюдение") {
                    NavigationLink("Открыть исходную версию") { MappingObservationDetail(record: original, historical: true, historicalVersion: 1) }
                        .accessibilityIdentifier("mappingOriginalVersion")
                    Text("Полевая дата: \(MappingDateText.format(original))").font(.caption)
                }
                let revisions = mapping.workflow?.journal.history(for: observationID) ?? []
                ForEach(Array(revisions.enumerated()), id: \.element.id) { index, revision in
                    Section("Версия \(revision.version)") {
                        LabeledContent("Исправлено", value: MappingCorrectionDateText.format(revision.correctedAt))
                        LabeledContent("Автор", value: revision.author ?? "Не указан")
                        Text(revision.reason).accessibilityIdentifier("revisionReason-\(revision.version)")
                        NavigationLink("Открыть версию \(revision.version)") { MappingObservationDetail(record: revision.snapshot, historical: true, historicalVersion: revision.version) }
                        NavigationLink("Сравнить с версией \(revision.version - 1)") {
                            MappingRevisionComparison(before: index == 0 ? original : revisions[index - 1].snapshot, after: revision.snapshot)
                        }.accessibilityIdentifier("compareRevision-\(revision.version)")
                        DisclosureGroup("Идентификаторы ревизии") {
                            Text(revision.id.uuidString)
                            Text("Предыдущая: \(revision.previousRevisionID?.uuidString ?? "исходное наблюдение")")
                        }.font(.caption).textSelection(.enabled)
                    }
                }
            }
        }.navigationTitle("История изменений").navigationBarTitleDisplayMode(.inline)
    }
}

private struct MappingRevisionComparison: View {
    let before: MappingObservation
    let after: MappingObservation
    var body: some View {
        List {
            Section("Изменённые поля") {
                ForEach(MappingObservationDifference.fields(before: before, after: after), id: \.self) { Text($0) }
            }
            Section("Полные значения до и после") {
                NavigationLink("До исправления") { MappingObservationDetail(record: before, historical: true) }
                NavigationLink("После исправления") { MappingObservationDetail(record: after, historical: true) }
            }
        }.navigationTitle("Сравнение версий")
    }
}
