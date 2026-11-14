import SwiftUI
import UniformTypeIdentifiers

struct MappingExchangeImportView: View {
    @EnvironmentObject private var mapping: MappingModel
    @StateObject private var coordinator = MappingExchangePreviewCoordinator()
    @State private var picker = false
    @State private var kind: MappingImportSource.Kind = .regulatoryData
    @State private var review = RegulatoryDataImport.Review()
    @State private var assignment = RegulatoryDataProposal.Assignment()
    @State private var observationDate = Date()
    @State private var draftPickets: [String: String] = [:]
    @State private var selectedURL: URL?
    private var selection: MappingExchangeImport.Selection {
        get { coordinator.state.selection }
        nonmutating set { coordinator.updateSelection(newValue) }
    }
    @State private var confirming = false
    @State private var applying = false
    @State private var report: MappingExchangeImport.Report?
    @State private var applyError: String?

    var body: some View {
        let state = coordinator.state
        List {
            Section {
                Picker("Формат", selection: $kind) {
                    Text("FieldForge Exchange").tag(MappingImportSource.Kind.exchange)
                    Text("Регламент · Data A:AD").tag(MappingImportSource.Kind.regulatoryData)
                }.disabled(applying)
                Button("Выбрать книгу Excel…", systemImage: "doc.badge.plus") { picker = true }
                    .accessibilityIdentifier("exchangeSelectWorkbook").disabled(applying)
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                   let encoded = ProcessInfo.processInfo.environment["FIELD_FORGE_UI_EXCEL"],
                   let bytes = Data(base64Encoded: encoded) {
                    Button("Тестовая книга Excel") {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Тестовый набор.xlsx")
                        do {
                            try bytes.write(to: url, options: .atomic)
                            selectedURL = url
                            prepare(url)
                        } catch { applyError = error.localizedDescription }
                    }.accessibilityIdentifier("uiExcelFixture")
                }
                #endif
                if let selectedURL { LabeledContent("Файл", value: selectedURL.lastPathComponent) }
                if state.busy {
                    ProgressView("Проверка книги…")
                    let operationID = coordinator.operationID
                    Button("Отменить проверку", role: .cancel) { coordinator.cancel(operationID: operationID) }
                }
                if applying { ProgressView("Сохранение выбранных строк…") }
                if let message = applyError ?? state.message { Text(message).foregroundStyle(.red) }
                if state.preview == nil, let entries = mapping.workflow?.journal.importLedger?.entries,
                   entries.contains(where: { $0.operation.source.kind == kind && $0.outcome == .pending }) {
                    Text("Есть незавершённый импорт. Выберите ту же книгу, чтобы продолжить или отклонить строки.")
                        .foregroundStyle(.orange)
                }
            }
            if kind == .regulatoryData, selectedURL != nil,
               let preview = state.preview, preview.productionInput == nil || (!preview.workbookBlocked && !preview.records.isEmpty),
               let workflow = mapping.workflow {
                assignmentSection(workflow.journal)
            }
            if let report {
                reportSection(report)
                if let selectedURL {
                    Button("Проверить эту книгу снова") { prepare(selectedURL) }.disabled(applying)
                }
            } else if let preview = state.preview, let selectedURL, let input = preview.productionInput {
                if !preview.workbookBlocked && !preview.records.isEmpty {
                    previewSections(preview, stale: state.stale, mixed: true)
                }
                RegulatorySourceImportSection(input: input, notices: preview.workbookBlockReasons, url: selectedURL,
                                              native: preview.workbookBlocked ? nil : preview,
                                              nativePreviewCurrent: !state.stale && !state.busy)
                    .id(input.workbookSHA256)
            } else if let preview = state.preview {
                previewSections(preview, stale: state.stale)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Импорт Excel")
        .navigationBarBackButtonHidden(applying)
        .fileImporter(isPresented: $picker, allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data]) { result in
            guard coordinator.isActive, !applying else { return }
            switch result {
            case .success(let url):
                if selectedURL != url {
                    coordinator.clear()
                    review = .init(); draftPickets = [:]
                }
                selectedURL = url; prepare(url)
            case .failure(let error): coordinator.selectionFailed(error)
            }
        }
        .alert("Подтвердить импорт?", isPresented: $confirming) {
            Button("Подтвердить") { confirm() }
                .disabled(!canConfirm(state.preview, stale: state.stale))
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выбрано для импорта: \(selection.accepted.count). Выбрано для отклонения: \(selection.rejectedPending.count + selection.rejectedConflicts.count). Каждое наблюдение сохраняется отдельно. Сохраняются только отмеченные изменения без конфликтов.")
        }
        .onChange(of: kind) { _, _ in
            coordinator.clear()
            selectedURL = nil; review = .init(); draftPickets = [:]
            report = nil; applyError = nil
        }
        .onAppear {
            coordinator.activate(generation: mapping.workflow?.committed.generationID)
            if assignment.projectID == nil {
                assignment.projectID = mapping.workflow?.context.projectID
                assignment.horizonID = mapping.workflow?.context.horizonID
            }
        }
        .onChange(of: state.publicationID) { _, _ in
            guard let source = coordinator.state.preview?.source, source.kind == .regulatoryData else { return }
            let documentID = RegulatoryDataImport.reviewDocumentID(source)
            if let previous = review.documentID, previous != documentID {
                review = .init(); draftPickets = [:]
            }
            review.documentID = documentID
        }
        .task(id: state.publicationID) {
            guard let id = state.publicationID else { return }
            let storage = mapping.storage
            while !Task.isCancelled && coordinator.isActive && coordinator.state.publicationID == id && !coordinator.state.stale {
                await coordinator.refresh(id) { try await storage.exchangePreviewIsCurrent($0) }
                if coordinator.state.publicationID != id || coordinator.state.stale { break }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onChange(of: mapping.workflow?.committed.generationID) { _, generation in coordinator.journalChanged(to: generation) }
        .onDisappear { coordinator.deactivate() }
    }

    @ViewBuilder private func previewSections(_ preview: MappingExchangePreview, stale: Bool, mixed: Bool = false) -> some View {
        let canChoose = !stale && !preview.workbookBlocked && !applying
        Section("Предварительная проверка") {
            if kind == .exchange { LabeledContent("Проект", value: preview.projectName) }
            if preview.exportedAt != .distantPast {
                LabeledContent("Выгружено", value: preview.exportedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if kind == .regulatoryData {
                LabeledContent("Сопоставлено наблюдений", value: String(Set(preview.records.compactMap(\.matchedID)).count))
            }
            if let scanned = preview.worksheetRowsScanned {
                LabeledContent("Прочитано строк листа Data", value: String(scanned))
                LabeledContent("Строки для проверки", value: String(preview.rowsProcessed))
            } else {
                LabeledContent("Проверено строк наблюдений", value: String(preview.rowsProcessed))
            }
            ForEach(categories, id: \.self) { category in
                LabeledContent(category.title, value: String(preview.count(category)))
            }
            if stale {
                Text("Журнал изменился после проверки. Проверьте книгу снова.")
                    .foregroundStyle(.orange).accessibilityIdentifier("exchangePreviewStale")
                if let selectedURL {
                    Button("Проверить книгу снова") { prepare(selectedURL) }.disabled(applying)
                }
            }
            if preview.workbookBlocked {
                if preview.workbookBlockReasons.isEmpty {
                    Text("Защищённые данные книги изменены. Исправьте ошибки или выгрузите новую книгу.")
                        .foregroundStyle(.orange)
                } else {
                    ForEach(preview.workbookBlockReasons, id: \.self) { reason in
                        Text(reason).foregroundStyle(.orange)
                    }
                }
            }
        }
        ForEach(categories, id: \.self) { category in
            let records = preview.records.filter { $0.classification == category }
            if !records.isEmpty, category != .unchanged || records.contains(where: { $0.receipt != nil || !$0.candidates.isEmpty }) {
                Section(category.title) {
                    ForEach(records) { record in
                        DisclosureGroup {
                            Text(record.reason)
                            if kind == .regulatoryData { regulatoryControls(record).disabled(!canChoose) }
                            ForEach(record.visibleChanges) { change in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: change.title).font(.subheadline.bold())
                                    LabeledContent(kind == .exchange ? "В выгрузке" : "В журнале") {
                                        Text(verbatim: change.before.isEmpty ? "Пусто" : change.before)
                                    }
                                    LabeledContent("Предложено") {
                                        Text(verbatim: change.after.isEmpty ? "Пусто" : change.after)
                                    }
                                }.font(.caption)
                            }
                            if record.canApply && !mixed {
                                Toggle(record.receipt?.outcome == .pending ? "Продолжить импорт" : "Принять изменение",
                                       isOn: decision(record.id, accepting: true))
                                    .disabled(!canChoose)
                            }
                            if record.canRejectPending && !mixed {
                                Toggle("Отклонить незавершённую строку", isOn: decision(record.id, accepting: false))
                                    .disabled(!canChoose)
                            } else if record.canRejectConflict && !mixed {
                                Toggle("Сохранить решение об отклонении", isOn: conflictDecision(record.id))
                                    .disabled(!canChoose)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.label.isEmpty ? record.reason : record.label)
                                Text(record.location).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        if !mixed, preview.records.contains(where: { $0.canApply || $0.classification == .conflict || $0.receipt?.outcome == .pending }) {
            Section {
                if kind == .regulatoryData, preview.records.contains(where: \.canApply) {
                    Button("Отметить все готовые наблюдения") {
                        selection.accepted = Set(preview.records.filter(\.canApply).map(\.id))
                        selection.rejectedPending.subtract(selection.accepted)
                    }.disabled(!canChoose)
                }
                Button("Проверить выбор и подтвердить", systemImage: "checkmark.circle") { confirming = true }
                    .disabled(!canConfirm(preview, stale: stale))
                if kind == .exchange {
                    Text("Для конфликта с журналом нужна новая выгрузка.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var categories: [MappingExchangePreview.Classification] {
        MappingExchangePreview.Classification.allCases.filter { kind == .regulatoryData || $0 != .ambiguous }
    }

    private func reportSection(_ report: MappingExchangeImport.Report) -> some View {
        Section("Результат импорта") {
            if report.interrupted || report.count(.pending) > 0 || report.count(.notProcessed) > 0 {
                Text("Импорт прерван или есть незавершённые строки. Сохранённые строки остаются в журнале.")
                    .foregroundStyle(.orange)
            }
            ForEach(MappingExchangeImport.Result.Status.allCases, id: \.self) { status in
                LabeledContent(status.title, value: String(report.count(status)))
            }
            let details = report.rows.filter { !$0.detail.isEmpty }
            if !details.isEmpty {
                DisclosureGroup("Подробности") {
                    ForEach(details) { row in
                        VStack(alignment: .leading) {
                            Text(row.label).font(.subheadline.bold())
                            Text(row.detail).font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func decision(_ id: String, accepting: Bool) -> Binding<Bool> {
        Binding(get: { (accepting ? selection.accepted : selection.rejectedPending).contains(id) }, set: { enabled in
            if accepting {
                if enabled { selection.accepted.insert(id); selection.rejectedPending.remove(id) }
                else { selection.accepted.remove(id) }
            } else {
                if enabled { selection.rejectedPending.insert(id); selection.accepted.remove(id) }
                else { selection.rejectedPending.remove(id) }
            }
        })
    }

    private func conflictDecision(_ id: String) -> Binding<Bool> {
        Binding(get: { selection.rejectedConflicts.contains(id) }, set: { enabled in
            if enabled { selection.rejectedConflicts.insert(id) }
            else { selection.rejectedConflicts.remove(id) }
        })
    }

    private func assignmentSection(_ journal: MappingJournal) -> some View {
        Section {
            DisclosureGroup("Контекст новых строк и координат") {
                Picker("Проект", selection: $assignment.projectID) {
                    Text("Выберите проект").tag(UUID?.none)
                    ForEach(journal.projects) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Горизонт", selection: $assignment.horizonID) {
                    Text("Выберите горизонт").tag(UUID?.none)
                    ForEach(journal.horizons.filter { $0.projectID == assignment.projectID }) {
                        Text($0.displayName).tag(Optional($0.id))
                    }
                }
                Picker("Выработка", selection: $assignment.excavationID) {
                    Text("По названию в столбце ID").tag(UUID?.none)
                    ForEach(journal.excavations.filter {
                        $0.projectID == assignment.projectID && $0.horizonIDs.contains(where: { $0 == assignment.horizonID })
                    }) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Дата и время наблюдения", selection: $observationDate)
                LabeledContent("Часовой пояс", value: assignment.zoneID)
                Picker("Система пикетажа", selection: $assignment.convention) {
                    Text("Выберите систему").tag(PicketConvention?.none)
                    Text("ПК 10 м").tag(Optional(PicketConvention.tenMeters))
                    Text("Километры + метры").tag(Optional(PicketConvention.legacyMeters))
                }
                TextField("Начало и направление отсчёта", text: $assignment.chainageOrigin)
                Picker("Координаты X/Y из Excel", selection: $assignment.planID) {
                    Text("Система XY пока неизвестна").tag(UUID?.none)
                    ForEach(journal.plans.filter {
                        $0.horizonID == assignment.horizonID && !$0.isDeleted && $0.file?.units != PlanUnits.unknown && $0.file != nil
                    }) { plan in
                        if let file = plan.file {
                            Text("\(file.originalFilename) · \(plan.version) · \(file.units.label)").tag(Optional(plan.id))
                        }
                    }
                }
                Picker("Север для новых азимутов", selection: $assignment.north) {
                    Text("Неизвестен").tag(GeographicReference.unknown)
                    Text("Сеточный").tag(GeographicReference.gridNorth)
                    Text("Истинный").tag(GeographicReference.trueNorth)
                    Text("Магнитный").tag(GeographicReference.magneticNorth)
                }
                Toggle("Азимут вертикальных плоскостей — условная сторона падения", isOn: $assignment.verticalSide)
                Button("Применить параметры к строкам без отдельного контекста") {
                    review.assignment = declaredAssignment
                    recheck()
                }
            }
            .onChange(of: assignment.projectID) { _, _ in
                assignment.horizonID = nil; assignment.excavationID = nil; assignment.planID = nil
            }
            .onChange(of: assignment.horizonID) { _, _ in assignment.excavationID = nil; assignment.planID = nil }
        }.disabled(applying || coordinator.state.busy)
    }

    private var declaredAssignment: RegulatoryDataProposal.Assignment {
        var value = assignment
        value.observedAt = observationDate
        return value
    }

    @ViewBuilder private func regulatoryControls(_ record: MappingExchangePreview.Record) -> some View {
        if let key = record.reviewID, let actions = record.regulatoryActions {
            if !record.candidates.isEmpty {
                Picker("Наблюдение в журнале", selection: Binding(get: { review.matches[key] }, set: { id in
                    review.matches[key] = id
                    review.faultMatches[key] = nil
                    review.createSeparately.remove(key)
                    recheck()
                })) {
                    Text("Выберите наблюдение").tag(UUID?.none)
                    ForEach(record.candidates) { candidate in Text(candidate.label).tag(Optional(candidate.id)) }
                }
            }
            if let rock = actions.rockKey {
                Picker("ROCK \(rock.numericValue) · код для проекта", selection: Binding(get: { review.rockCodes[rock] }, set: { code in
                    review.rockCodes[rock] = code
                    recheck()
                })) {
                    Text("Выберите точный код").tag(String?.none)
                    ForEach(actions.rockChoices) { choice in
                        Text([choice.code, choice.name].compactMap { $0 }.joined(separator: " · ")).tag(Optional(choice.code))
                    }
                }
            }
            if actions.canCreateSeparately {
                Button("Создать отдельное наблюдение") { review.createSeparately.insert(key); recheck() }
            }
            if actions.canFindExisting {
                Button("Найти другое наблюдение") { review.findExisting.insert(key); recheck() }
            }
            if actions.canGroup {
                Button("Один объект с несколькими разломами") { review.groupFaults.insert(key); recheck() }
            }
            if actions.canSplit {
                Button("Разделить на отдельные наблюдения") { review.splitFaults.insert(key); recheck() }
            }
            if actions.canResolveConflict, let graph = record.graphFingerprint {
                Button("Использовать правки Excel поверх текущей версии") { review.takeExcelChanges[key] = graph; recheck() }
            }
            if actions.canPreservePrecision {
                Button("Сохранить точные числа журнала") { review.preservePrecision.insert(key); recheck() }
            }
            if actions.canAcknowledgeDerived {
                Button("Продолжить с сохранёнными SD и GSI") { review.acknowledgeDerived.insert(key); recheck() }
            }
            ForEach(actions.faultMatches) { fault in
                Picker("Разлом · строка \(fault.row) · \(fault.values)", selection: Binding(get: {
                    review.faultMatches[key]?[fault.id]
                }, set: { id in
                    review.faultMatches[key, default: [:]][fault.id] = id
                    recheck()
                })) {
                    Text("Новый разлом / выберите сохранённый").tag(UUID?.none)
                    ForEach(fault.choices) { choice in Text(choice.label).tag(Optional(choice.id)) }
                }
            }
            if actions.needsPicket {
                TextField("Пикет", text: Binding(get: { draftPickets[key] ?? "" }, set: { draftPickets[key] = $0 }))
                Button("Применить пикет") { review.pickets[key] = draftPickets[key]; recheck() }
            }
            if record.matchedID == nil && record.receipt == nil {
                Button("Использовать текущий контекст только для этих строк") {
                    review.assignments[key] = declaredAssignment
                    recheck()
                }
            }
        }
    }

    private func recheck() {
        if let selectedURL { prepare(selectedURL) }
    }

    private func prepare(_ url: URL) {
        report = nil; applyError = nil
        coordinator.prepare(url, work: .init(storage: mapping.storage, kind: kind, regulatoryReview: review))
    }

    private func canConfirm(_ preview: MappingExchangePreview?, stale: Bool) -> Bool {
        guard !stale, !applying, !mapping.isSaving, let preview, !preview.workbookBlocked else { return false }
        return selection.hasAction(in: preview)
    }

    private func confirm() {
        let state = coordinator.state
        guard let preview = state.preview, let selectedURL, canConfirm(preview, stale: state.stale) else { return }
        applying = true
        applyError = nil
        let approved = selection
        Task {
            defer { applying = false }
            do { report = try await mapping.applyExchange(preview, url: selectedURL, selection: approved) }
            catch { applyError = error.localizedDescription }
        }
    }
}

private struct RegulatorySourceImportSection: View {
    @EnvironmentObject private var mapping: MappingModel
    let input: RegulatorySourceImport.Input
    let notices: [String]
    let url: URL
    let native: MappingExchangePreview?
    let nativePreviewCurrent: Bool
    private var nativeReady: Bool {
        guard let native else { return true }
        return nativePreviewCurrent && native.records.allSatisfy {
            $0.canApply || $0.classification == .unchanged || $0.receipt?.outcome == .applied
        }
    }
    @State private var review = RegulatorySourceImport.Review()
    @State private var plan: RegulatorySourceImport.Plan?
    @State private var task: Task<Void, Never>?
    @State private var message: String?
    @State private var saved = false
    @State private var didInitialize = false
    @State private var editingSettings = false
    @FocusState private var datasetFocused: Bool
    @State private var confirm = false

    init(input: RegulatorySourceImport.Input, notices: [String], url: URL, native: MappingExchangePreview?,
         nativePreviewCurrent: Bool) {
        self.input = input; self.notices = notices; self.url = url; self.native = native
        self.nativePreviewCurrent = nativePreviewCurrent
    }

    private var snapshot: MappingCommittedSnapshot? { mapping.workflow?.committed }
    private var dataset: String { review.dataset.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            Section("Импорт наблюдений") {
                if saved {
                    Label("Наблюдения сохранены", systemImage: "checkmark.circle")
                    NavigationLink("Открыть журнал") {
                        MappingJournalView(importedProjectID: review.projectID, importedDataset: input.bindings.isEmpty ? dataset : input.suggestedDataset)
                    }.accessibilityIdentifier("openImportedJournal")
                } else {
                    if input.bindings.isEmpty { sourceSetup }
                    if let message { Text(message).foregroundStyle(.orange) }
                    if task != nil {
                        ProgressView("Обработка набора…")
                        Button("Отменить", role: .cancel) { task?.cancel() }.disabled(mapping.isSaving)
                    }
                    if let plan, !plan.blocked, (plan.canApply || native?.records.contains(where: \.canApply) == true) {
                        Button("Импортировать наблюдения") { datasetFocused = false; confirm = true }
                            .buttonStyle(.borderedProminent).disabled(!canSave(plan)).accessibilityIdentifier("importSourceObservations")
                    } else if let plan, !plan.blocked, plan.count(.unchanged) > 0 {
                        NavigationLink("Открыть журнал") {
                            MappingJournalView(importedProjectID: review.projectID, importedDataset: input.bindings.isEmpty ? dataset : input.suggestedDataset)
                        }
                    }
                    if let plan { summary(plan) }
                    if !notices.isEmpty {
                        DisclosureGroup("Сведения о формате") {
                            ForEach(notices, id: \.self) { Text($0).font(.caption) }
                        }
                    }
                    if plan == nil, task == nil {
                        Button("Проверить импорт") { compare() }.disabled(review.projectID == nil && input.bindings.isEmpty)
                    }
                }
            }
            if !saved, let plan {
                if plan.blocked || plan.count(.invalid) > 0 {
                    Section("Строки, требующие внимания") {
                        if plan.blocked && plan.count(.conflict) == 0 {
                            Text("Повторяются исходные ID. Исправьте идентификаторы в книге.")
                        }
                        let invalid = plan.changes.filter { $0.kind == .invalid }
                        if !invalid.isEmpty {
                            DisclosureGroup("Ошибки строк · \(invalid.count)") {
                                ForEach(invalid) { change in
                                    LabeledContent("Data!\(change.row) · \(change.sourceID)", value: change.reason)
                                }
                            }
                        }
                        conflictControls(plan)
                    }
                }
                if !nativeReady { Text("Проверьте обычные наблюдения из этой книги.").foregroundStyle(.orange) }
            }
        }
        .alert("Импортировать наблюдения одним пакетом?", isPresented: $confirm) {
            Button("Импортировать") { apply() }
            Button("Отмена", role: .cancel) {}
        } message: {
            if let plan, plan.count(.invalid) > 0 { Text("Строки с ошибками будут пропущены: \(plan.count(.invalid)).") }
        }
        .sheet(isPresented: $editingSettings, onDismiss: compare) {
            NavigationStack {
                Form { RegulatoryDatasetSettingsFields(review: $review) }
                    .navigationTitle("Параметры набора")
                    .scrollDismissesKeyboard(.interactively)
                    .toolbar { Button("Готово") { editingSettings = false; compare() } }
            }
        }
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            review.projectID = input.suggestedProjectID ?? mapping.workflow?.context.projectID
            let exactDatasets = Set((snapshot?.journal.regulatorySourceObservations ?? []).filter {
                $0.key.projectID == review.projectID && $0.versions.contains { $0.workbookSHA256 == input.workbookSHA256 }
            }.map(\.key.dataset))
            review.dataset = input.suggestedDataset ?? (exactDatasets.count == 1 ? exactDatasets.first : nil) ??
                url.deletingPathExtension().lastPathComponent
            loadDataset()
            compare()
        }
        .onDisappear { task?.cancel() }
    }

    private var sourceSetup: some View {
        Group {
            Picker("Проект", selection: $review.projectID) {
                Text("Выберите проект").tag(UUID?.none)
                ForEach(snapshot?.journal.projects ?? []) { Text($0.name).tag(Optional($0.id)) }
            }.onChange(of: review.projectID) { _, _ in loadDataset(); compare() }
            TextField("Постоянное имя набора", text: $review.dataset)
                .textInputAutocapitalization(.never).submitLabel(.done).focused($datasetFocused)
                .accessibilityIdentifier("regulatoryDatasetName")
                .onSubmit { datasetFocused = false }
                .onChange(of: review.dataset) { _, _ in plan = nil }
                .onChange(of: datasetFocused) { _, focused in if !focused { loadDataset(); compare() } }
                .toolbar {
                    if datasetFocused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Готово") { datasetFocused = false }
                        }
                    }
                }
            let datasets = Set((snapshot?.journal.regulatorySourceObservations ?? [])
                .filter { $0.key.projectID == review.projectID }.map(\.key.dataset))
            if !datasets.isEmpty {
                Menu("Выбрать существующий набор") {
                    ForEach(datasets.sorted(), id: \.self) { name in
                        Button(name) { review.dataset = name; loadDataset(); compare() }
                    }
                }
            }
            Picker("Север для азимутов Excel", selection: Binding(get: { review.north ?? .unknown }, set: {
                review.north = $0
                compare()
            })) {
                ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
            }
            Button("Координаты и правила DXF") { datasetFocused = false; editingSettings = true }
        }.disabled(task != nil)
    }

    private func loadDataset() {
        let existing = snapshot?.journal.regulatorySourceObservations?.filter {
            $0.key.projectID == review.projectID && $0.key.dataset == dataset
        } ?? []
        let frames = Set(existing.compactMap { $0.latest?.frame })
        let saved = review.projectID.flatMap { snapshot?.projects[$0]?.regulatoryDatasets?[dataset] }
        review.frame = saved?.frame ?? input.suggestedFrame ?? (frames.count == 1 ? frames.first : nil) ?? .init()
        review.frameConfirmed = true
        review.north = saved?.north
        review.displayPlans = []
        review.geometryRules = [:]
        review.ranges = [:]
        review.resolutions = [:]
    }

    @ViewBuilder private func summary(_ plan: RegulatorySourceImport.Plan) -> some View {
        let valid = plan.changes.filter { $0.kind != .invalid }
        let ready = valid.filter { $0.kind != .conflict }
        let ambiguous = ready.filter { $0.matchingIssue?.isAmbiguous == true }.count
        LabeledContent("Строки без ошибок", value: String(valid.count))
        ForEach([MappingExchangePreview.Classification.new, .correction, .unchanged, .conflict, .invalid], id: \.self) {
            LabeledContent($0.title, value: String(plan.count($0)))
        }
        LabeledContent("Горизонт определён автоматически", value: String(ready.filter(\.automatic).count))
        LabeledContent("Горизонт не определён", value: String(ready.filter { $0.destination.horizonID == nil }.count - ambiguous))
            .accessibilityIdentifier("sourceUnresolvedCount")
        if ambiguous > 0 { LabeledContent("Несколько горизонтов", value: String(ambiguous)) }
        if plan.generationID != snapshot?.generationID {
            Button("Обновить проверку") { compare() }
        }
    }

    private func canSave(_ plan: RegulatorySourceImport.Plan) -> Bool {
        !plan.blocked && (plan.canApply || native?.records.contains(where: \.canApply) == true)
            && nativeReady && snapshot?.generationID == plan.generationID && task == nil && !mapping.isSaving && !datasetFocused
    }

    @ViewBuilder private func conflictControls(_ plan: RegulatorySourceImport.Plan) -> some View {
        let conflicts = plan.changes.flatMap(\.conflicts)
        if !conflicts.isEmpty {
            ForEach(conflicts, id: \.self) { conflict in
                let sourceID = plan.changes.first { $0.conflicts.contains(conflict) }?.sourceID ?? ""
                DisclosureGroup("\(sourceID) · \(RegulatoryDataWorkbook.columns[conflict.column])") {
                    LabeledContent("Исходное", value: conflict.baseline.isEmpty ? "Пусто" : conflict.baseline)
                    LabeledContent("В журнале", value: conflict.local.isEmpty ? "Пусто" : conflict.local)
                    LabeledContent("В Excel", value: conflict.incoming.isEmpty ? "Пусто" : conflict.incoming)
                    Picker("Решение", selection: Binding(get: { review.resolutions[conflict] }, set: { review.resolutions[conflict] = $0 })) {
                        Text("Выберите").tag(RegulatorySourceImport.Choice?.none)
                        Text("Оставить значение журнала").tag(Optional(RegulatorySourceImport.Choice.keepLocal))
                        Text("Принять Excel").tag(Optional(RegulatorySourceImport.Choice.acceptExcel))
                    }
                }
            }
            Button("Проверить решения") { compare() }
            Button("Отменить импорт", role: .cancel) {
                review.resolutions.removeAll()
                self.plan = nil
            }
        }
    }

    private func compare() {
        guard (input.bindings.isEmpty == false || review.projectID != nil), task == nil, let snapshot else { return }
        datasetFocused = false
        plan = nil
        message = nil
        let review = self.review
        let input = self.input
        let plans = mapping.planStore
        task = Task {
            defer { task = nil }
            let work = Task.detached(priority: .userInitiated) {
                try RegulatorySourceImport.prepare(input, review: review, snapshot: snapshot, plans: plans)
            }
            do {
                plan = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            } catch { message = error.localizedDescription }
        }
    }

    private func apply() {
        guard let plan, canSave(plan) else { return }
        let url = self.url
        let native = self.native
        task = Task {
            defer { task = nil }
            do {
                let work = Task.detached(priority: .userInitiated) {
                    let bytes = try await MappingExchangeFileRead.data(url: url)
                    guard ExchangeBaseline.hash(bytes) == plan.workbookSHA256 else {
                        throw ExchangeImportError("Файл изменился после проверки. Выберите книгу снова.")
                    }
                    return try native.map { preview in
                        try MappingExchangeImport.Batch(preview: preview, bytes: bytes,
                            selection: .init(accepted: Set(preview.records.filter(\.canApply).map(\.id))),
                            now: Date(), mixed: true)
                    }
                }
                let batch = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                if let batch {
                    try await mapping.applyMixedExchange(batch, sourcePlan: plan)
                } else {
                    try await mapping.persist { workflow in
                        try workflow.commit(RegulatorySourceImport.applying(plan, to: workflow.committed))
                    }
                }
                self.plan = nil
                saved = true
            } catch { message = error.localizedDescription }
        }
    }
}

struct RegulatoryDatasetSetupView: View {
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let dataset: String
    @State private var review = RegulatorySourceImport.Review()
    @State private var error: String?

    var body: some View {
        Form {
            RegulatoryDatasetSettingsFields(review: $review)
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(dataset)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                Button("Сохранить") { save() }.disabled(mapping.isSaving || review.projectID == nil)
            }
            .task {
                guard review.projectID == nil else { return }
                let current = mapping.workflow?.committed
                let saved = current?.projects[projectID]?.regulatoryDatasets?[dataset]
                let frames = Set((current?.journal.regulatorySourceObservations ?? []).filter {
                    $0.key.projectID == projectID && $0.key.dataset == dataset
                }.compactMap { $0.latest?.frame })
                review = .init(projectID: projectID, dataset: dataset, frame: saved?.frame ?? (frames.count == 1 ? frames.first : nil) ?? .init(),
                               frameConfirmed: true, north: saved?.north)
            }
    }

    private func save() {
        let review = self.review
        let plans = mapping.planStore
        Task {
            do {
                try await mapping.persist { workflow in
                    let snapshot = workflow.committed
                    let preview = try RegulatorySourceImport.prepare(.init(rows: [], workbookSHA256: ""), review: review, snapshot: snapshot, plans: plans)
                    if preview.canApply { try workflow.commit(RegulatorySourceImport.applying(preview, to: snapshot)) }
                }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct RegulatoryDatasetSettingsFields: View {
    @EnvironmentObject private var mapping: MappingModel
    @Binding var review: RegulatorySourceImport.Review
    @State private var rangeHorizon: UUID?
    @State private var minimum = ""
    @State private var maximum = ""
    @State private var geometryPlan: UUID?
    @State private var geometryExcavation: UUID?
    @State private var maximumXY = ""
    @State private var maximumZ = ""
    @State private var message: String?
    @State private var useGeometry = false
    @FocusState private var focused: Bool

    private var snapshot: MappingCommittedSnapshot? { mapping.workflow?.committed }
    private var horizons: [MappingHorizon] { snapshot?.journal.horizons.filter { $0.projectID == review.projectID } ?? [] }
    private var associations: [UUID: RegulatorySourceImport.PlanAssociation] {
        guard let id = review.projectID else { return [:] }
        return snapshot?.projects[id]?.regulatoryDatasets?[review.dataset.trimmingCharacters(in: .whitespacesAndNewlines)]?.plans ?? [:]
    }

    var body: some View {
        let available = (snapshot?.journal.plans ?? []).filter { plan in
            !plan.isDeleted && !plan.isArchived && horizons.contains { $0.id == plan.horizonID } &&
                plan.file.map { PlanElevationSnap.metersPerUnit($0) != nil } == true
        }
        let plan = available.first { $0.id == geometryPlan }
        Section("Система координат набора") {
            TextField("Система координат XY", text: $review.frame.crs).focused($focused)
            TextField("Оси XY", text: $review.frame.axes).focused($focused)
            Picker("Единицы XY", selection: $review.frame.xyUnits) {
                Text("Неизвестны").tag("")
                Text("Метры").tag("m")
                Text("Миллиметры").tag("mm")
                Text("Единицы чертежа").tag("drawing")
            }
            TextField("Вертикальный датум", text: $review.frame.verticalDatum).focused($focused)
            Text("Z в Excel задана в метрах. Укажите только известные метаданные.").font(.caption)
        }
        Section("Связь набора с DXF") {
            Picker("Ревизия плана", selection: $geometryPlan) {
                Text("Выберите DXF").tag(UUID?.none)
                ForEach(available) { plan in
                    Text("\(horizons.first { $0.id == plan.horizonID }?.displayName ?? "DXF") · \(plan.version)").tag(Optional(plan.id))
                }
            }.onChange(of: geometryPlan) { _, id in
                geometryExcavation = nil
                let rule = id.flatMap { review.geometryRules[$0] ?? associations[$0]?.geometry }
                useGeometry = rule != nil
                maximumXY = rule.map { ElevationInput.text($0.maximumXYMeters) } ?? ""
                maximumZ = rule.map { ElevationInput.text($0.maximumZMeters) } ?? ""
                geometryExcavation = rule?.excavationID
            }
            if let plan, let file = plan.file {
                LabeledContent("СК и оси плана", value: "\(file.crs) · \(file.axes)")
                LabeledContent("Единицы плана", value: file.units.label)
                Toggle("Искать горизонт по 3D-геометрии", isOn: $useGeometry)
                if useGeometry {
                    Picker("Подтверждённая выработка", selection: $geometryExcavation) {
                        Text("Не назначать").tag(UUID?.none)
                        ForEach((snapshot?.journal.excavations ?? []).filter {
                            $0.projectID == review.projectID && $0.horizonIDs.contains(plan.horizonID)
                        }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Допуск XY до сегмента, м", text: $maximumXY).keyboardType(.decimalPad).focused($focused)
                    TextField("Допуск Z, м", text: $maximumZ).keyboardType(.decimalPad).focused($focused)
                }
                Button(useGeometry ? "Подтвердить совпадение СК и датума Z" : "Подтвердить совпадение СК и осей XY") {
                    confirm(plan: plan, file: file)
                }
            }
            ForEach(available.filter { review.displayPlans.contains($0.id) || associations[$0.id]?.supportsXY($0, frame: review.frame) == true }) {
                LabeledContent($0.file?.originalFilename ?? $0.version, value: "СК подтверждена")
            }
        }
        if PlanCoordinateCompatibility.known(review.frame.verticalDatum) != nil {
            Section("Подтверждённые диапазоны горизонтов") {
                Picker("Горизонт", selection: $rangeHorizon) {
                    Text("Выберите горизонт").tag(UUID?.none)
                    ForEach(horizons.filter { $0.elevationDatum == review.frame.verticalDatum }) { Text($0.displayName).tag(Optional($0.id)) }
                }.onChange(of: rangeHorizon) { _, id in
                    let range = id.flatMap { review.ranges[$0] ?? snapshot?.horizons[$0]?.regulatoryElevationRange }
                    minimum = range.map { ElevationInput.text($0.minimum) } ?? ""
                    maximum = range.map { ElevationInput.text($0.maximum) } ?? ""
                }
                TextField("Нижняя отметка Z, м", text: $minimum).keyboardType(.numbersAndPunctuation).focused($focused)
                TextField("Верхняя отметка Z, м", text: $maximum).keyboardType(.numbersAndPunctuation).focused($focused)
                Button("Подтвердить диапазон") { addRange() }.disabled(rangeHorizon == nil)
                ForEach(horizons) { horizon in
                    if let range = review.ranges[horizon.id] ?? horizon.regulatoryElevationRange {
                        LabeledContent(horizon.displayName, value: "\(ElevationInput.text(range.minimum))…\(ElevationInput.text(range.maximum)) м")
                    }
                }
            }
        }
        if let message { Text(message).foregroundStyle(.orange) }
        Section {}.onChange(of: review.frame) { old, new in
            // A confirmation writes the plan's XY metadata together with its link.
            review.geometryRules = review.geometryRules.filter { $0.value.frame == new }
            review.displayPlans = review.displayPlans.filter { id in
                guard let file = snapshot?.plan(id: id)?.file else { return false }
                return file.crs == new.crs && file.axes == new.axes && file.units.coordinateUnits == new.xyUnits
            }
            if old.verticalDatum != new.verticalDatum { review.ranges = review.ranges.filter { $0.value.datum == new.verticalDatum } }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focused = false }
            }
        }
    }

    private func confirm(plan: MappingPlanReference, file: ManagedPlanFile) {
        focused = false
        do {
            guard PlanCoordinateCompatibility.known(file.crs) != nil, PlanCoordinateCompatibility.known(file.axes) != nil else {
                throw MappingError.invalid("Уточните СК и оси в метаданных ревизии DXF.")
            }
            var frame = review.frame
            guard [(frame.crs, file.crs), (frame.axes, file.axes)].allSatisfy({ declared, actual in
                PlanCoordinateCompatibility.known(declared).map { $0 == PlanCoordinateCompatibility.known(actual) } ?? true
            }), frame.xyUnits.isEmpty || frame.xyUnits == file.units.coordinateUnits else {
                throw MappingError.invalid("СК, оси или единицы набора и плана различаются.")
            }
            frame.crs = file.crs; frame.axes = file.axes; frame.xyUnits = file.units.coordinateUnits
            if useGeometry {
                let rule = try RegulatorySourceImport.GeometryRule(horizonID: plan.horizonID, excavationID: geometryExcavation, frame: frame,
                    maximumXYMeters: ElevationInput.meters(maximumXY), maximumZMeters: ElevationInput.meters(maximumZ))
                guard rule.valid, snapshot?.horizons[plan.horizonID]?.elevationDatum == frame.verticalDatum else {
                    throw MappingError.invalid("Укажите неотрицательные допуски и подтвердите общий вертикальный датум.")
                }
                review.geometryRules[plan.id] = rule
            } else { review.geometryRules[plan.id] = nil }
            review.frame = frame
            review.displayPlans.insert(plan.id)
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func addRange() {
        focused = false
        guard let id = rangeHorizon else { return }
        do {
            let range = try RegulatorySourceImport.ElevationRange(minimum: ElevationInput.meters(minimum),
                maximum: ElevationInput.meters(maximum), datum: review.frame.verticalDatum)
            guard range.valid else { throw MappingError.invalid("Проверьте нижнюю и верхнюю отметки.") }
            review.ranges[id] = range
            message = nil
        } catch { message = error.localizedDescription }
    }
}
