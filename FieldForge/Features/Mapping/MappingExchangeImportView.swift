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
            if kind == .regulatoryData, selectedURL != nil, state.preview?.productionInput == nil, let workflow = mapping.workflow {
                assignmentSection(workflow.journal)
            }
            if let report {
                reportSection(report)
                if let selectedURL {
                    Button("Проверить эту книгу снова") { prepare(selectedURL) }.disabled(applying)
                }
            } else if let preview = state.preview, let selectedURL, let input = preview.productionInput {
                RegulatorySourceImportSection(input: input, notices: preview.workbookBlockReasons, url: selectedURL)
                    .id(input.workbookSHA256)
            } else if let preview = state.preview {
                previewSections(preview, stale: state.stale)
            }
        }
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

    @ViewBuilder private func previewSections(_ preview: MappingExchangePreview, stale: Bool) -> some View {
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
                            if record.canApply {
                                Toggle(record.receipt?.outcome == .pending ? "Продолжить импорт" : "Принять изменение",
                                       isOn: decision(record.id, accepting: true))
                                    .disabled(!canChoose)
                            }
                            if record.canRejectPending {
                                Toggle("Отклонить незавершённую строку", isOn: decision(record.id, accepting: false))
                                    .disabled(!canChoose)
                            } else if record.canRejectConflict {
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
        if preview.records.contains(where: { $0.canApply || $0.classification == .conflict || $0.receipt?.outcome == .pending }) {
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
    @State private var review = RegulatorySourceImport.Review()
    @State private var plan: RegulatorySourceImport.Plan?
    @State private var task: Task<Void, Never>?
    @State private var message: String?
    @State private var rangeHorizon: UUID?
    @State private var minimum = ""
    @State private var maximum = ""
    @State private var geometryPlan: UUID?
    @State private var geometryExcavation: UUID?
    @State private var maximumXY = ""
    @State private var maximumZ = ""
    @State private var groupHorizon: UUID?
    @State private var unresolvedGroup = false
    @State private var bulkHorizon: UUID?
    @State private var bulkExcavation: UUID?
    @State private var selectedSources: Set<String> = []
    @State private var confirm = false

    private var snapshot: MappingCommittedSnapshot? { mapping.workflow?.committed }
    private var horizons: [MappingHorizon] {
        snapshot?.journal.horizons.filter { $0.projectID == review.projectID } ?? []
    }

    var body: some View {
        Section("Набор наблюдений") {
            LabeledContent("Исходные наблюдения", value: String(input.rows.count))
            Picker("Проект", selection: $review.projectID) {
                Text("Выберите проект").tag(UUID?.none)
                ForEach(snapshot?.journal.projects ?? []) { Text($0.name).tag(Optional($0.id)) }
            }.onChange(of: review.projectID) { _, _ in
                review.ranges = [:]
                review.geometryRules = [:]
                review.assignments = [:]
                selectedSources = []
                rangeHorizon = nil
                geometryPlan = nil
                plan = nil
            }
            TextField("Постоянное имя набора данных", text: $review.dataset)
                .textInputAutocapitalization(.never)
                .onChange(of: review.dataset) { _, _ in
                    review.assignments = [:]
                    selectedSources = []
                    plan = nil
                }
            let datasets = Set((snapshot?.journal.regulatorySourceObservations ?? [])
                .filter { $0.key.projectID == review.projectID }.map { $0.key.dataset })
            if !datasets.isEmpty {
                Menu("Сохранённые наборы") {
                    ForEach(datasets.sorted(), id: \.self) { name in
                        Button(name) { review.dataset = name }
                    }
                }
            }
            Text("Для следующей версии книги выберите тот же набор данных.")
                .font(.caption)
        }
        .disabled(task != nil)

        Section("Координаты набора") {
            TextField("Система координат XY", text: $review.frame.crs)
            TextField("Оси XY", text: $review.frame.axes)
            Picker("Единицы XY", selection: $review.frame.xyUnits) {
                Text("Неизвестны").tag("")
                Text("Метры").tag("m")
                Text("Миллиметры").tag("mm")
                Text("Единицы чертежа").tag("drawing")
            }
            TextField("Вертикальный датум", text: $review.frame.verticalDatum)
            Toggle("Подтвердить метаданные набора", isOn: $review.frameConfirmed)
            Text("Z — абсолютная отметка в метрах. Оставьте неизвестные метаданные пустыми.")
                .font(.caption)
        }
        .disabled(task != nil)
        .onChange(of: review.frame) { _, _ in
            review.frameConfirmed = false
            review.ranges = [:]
            review.geometryRules = [:]
            plan = nil
        }
        .onChange(of: review.frameConfirmed) { _, _ in plan = nil }

        if review.frameConfirmed && !review.frame.verticalDatum.isEmpty {
            Section {
                DisclosureGroup("Подтверждённые диапазоны горизонтов") {
                    Picker("Горизонт", selection: $rangeHorizon) {
                        Text("Выберите горизонт").tag(UUID?.none)
                        ForEach(horizons.filter { $0.elevationDatum == review.frame.verticalDatum }) {
                            Text($0.displayName).tag(Optional($0.id))
                        }
                    }
                    TextField("Нижняя отметка Z, м", text: $minimum)
                    TextField("Верхняя отметка Z, м", text: $maximum)
                    Button("Добавить диапазон к проверке") { addRange() }.disabled(rangeHorizon == nil)
                    ForEach(horizons) { horizon in
                        if let range = review.ranges[horizon.id] ?? horizon.regulatoryElevationRange {
                            LabeledContent(horizon.displayName, value: "\(ElevationInput.text(range.minimum))…\(ElevationInput.text(range.maximum)) м")
                        }
                    }
                }
            }.disabled(task != nil)
        }

        if review.frameConfirmed && !review.frame.verticalDatum.isEmpty {
            geometrySection
        }

        Section("Проверка импорта") {
            ForEach(notices, id: \.self) { Text($0).font(.caption) }
            if let message { Text(message) }
            if task != nil {
                ProgressView("Обработка набора…")
                Button("Отменить", role: .cancel) { task?.cancel() }.disabled(mapping.isSaving)
            }
            Button("Сопоставить набор") { compare() }.disabled(task != nil || !review.frameConfirmed)
            if let plan {
                LabeledContent("Назначен горизонт", value: String(plan.changes.filter { $0.destination.horizonID != nil }.count))
                LabeledContent("Назначена выработка", value: String(plan.changes.filter { $0.destination.excavationID != nil }.count))
                LabeledContent("Предложено новых горизонтов", value: "0")
                LabeledContent("Горизонт не определён", value: String(plan.changes.filter { $0.destination.horizonID == nil }.count))
                LabeledContent("Сопоставлено с журналом", value: String(plan.count(.unchanged) + plan.count(.correction) + plan.count(.conflict)))
                ForEach([MappingExchangePreview.Classification.new, .correction, .unchanged, .conflict, .invalid], id: \.self) {
                    LabeledContent($0.title, value: String(plan.count($0)))
                }
                bulkControls(plan)
                Button("Сохранить набор") { confirm = true }
                    .disabled(!plan.canApply || snapshot?.generationID != plan.generationID || task != nil || mapping.isSaving)
            }
        }
        .alert("Сохранить наблюдения одним пакетом?", isPresented: $confirm) {
            Button("Сохранить") { apply() }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear { if review.projectID == nil { review.projectID = mapping.workflow?.context.projectID } }
        .onDisappear { task?.cancel() }
    }

    private func bulkControls(_ plan: RegulatorySourceImport.Plan) -> some View {
        let group = plan.changes.filter { change in
            unresolvedGroup ? change.destination.horizonID == nil
                : groupHorizon == nil || groupHorizon == change.destination.horizonID
        }
        return DisclosureGroup("Строки набора и групповое назначение") {
            Picker("Группа по горизонту", selection: $groupHorizon) {
                Text("Весь набор").tag(UUID?.none)
                ForEach(horizons) { Text($0.displayName).tag(Optional($0.id)) }
            }.disabled(unresolvedGroup)
            Toggle("Только без горизонта", isOn: $unresolvedGroup)
            Button("Отметить группу · \(group.count)") { selectedSources.formUnion(group.map(\.sourceID)) }
                .disabled(group.isEmpty)
            if !selectedSources.isEmpty { Button("Снять отметки") { selectedSources.removeAll() } }
            Picker("Назначить горизонт", selection: $bulkHorizon) {
                Text("Без горизонта").tag(UUID?.none)
                ForEach(horizons) { Text($0.displayName).tag(Optional($0.id)) }
            }.onChange(of: bulkHorizon) { _, _ in bulkExcavation = nil }
            Picker("Назначить выработку", selection: $bulkExcavation) {
                Text("Без выработки").tag(UUID?.none)
                ForEach((snapshot?.journal.excavations ?? []).filter {
                    $0.projectID == review.projectID && $0.horizonIDs.contains { $0 == bulkHorizon }
                }) { Text($0.name).tag(Optional($0.id)) }
            }
            Button("Назначить · \(selectedSources.count) выбрано") {
                let context = MappingContext(projectID: review.projectID, horizonID: bulkHorizon, excavationID: bulkExcavation)
                for source in selectedSources { review.assignments[source] = context }
                selectedSources.removeAll()
                compare()
            }.disabled(selectedSources.isEmpty || task != nil)
            ForEach(group) { change in
                Toggle(isOn: Binding(get: { selectedSources.contains(change.sourceID) }, set: { selected in
                    if selected { selectedSources.insert(change.sourceID) }
                    else { selectedSources.remove(change.sourceID) }
                })) {
                    VStack(alignment: .leading) {
                        Text("\(change.sourceID) · Data!\(change.row)")
                        Text(change.reason).font(.caption)
                    }
                }
            }
        }
    }

    private var geometrySection: some View {
        let available = (snapshot?.journal.plans ?? []).filter { plan in
            guard let file = plan.file else { return false }
            return !plan.isDeleted && !plan.isArchived && horizons.contains { $0.id == plan.horizonID && $0.elevationDatum == review.frame.verticalDatum } &&
                file.crs == review.frame.crs && file.axes == review.frame.axes && file.units.coordinateUnits == review.frame.xyUnits
        }
        let horizon = available.first { $0.id == geometryPlan }?.horizonID
        return Section {
            DisclosureGroup("Подтверждённая геометрия DXF") {
                Picker("Ревизия плана", selection: $geometryPlan) {
                    Text("Выберите DXF").tag(UUID?.none)
                    ForEach(available) { plan in Text(plan.version).tag(Optional(plan.id)) }
                }.onChange(of: geometryPlan) { _, _ in geometryExcavation = nil }
                Picker("Выработка по этому DXF", selection: $geometryExcavation) {
                    Text("Без подтверждённой выработки").tag(UUID?.none)
                    ForEach((snapshot?.journal.excavations ?? []).filter {
                        $0.projectID == review.projectID && $0.horizonIDs.contains { $0 == horizon }
                    }) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Максимальное расстояние XY до сегмента, м", text: $maximumXY)
                TextField("Максимальное расхождение Z с сегментом, м", text: $maximumZ)
                Button("Подтвердить датум и принадлежность DXF") {
                    guard let horizon, let geometryPlan else { return }
                    do {
                        let rule = try RegulatorySourceImport.GeometryRule(horizonID: horizon,
                            excavationID: geometryExcavation, frame: review.frame,
                            maximumXYMeters: ElevationInput.meters(maximumXY), maximumZMeters: ElevationInput.meters(maximumZ))
                        guard rule.valid else { throw MappingError.invalid("Проверьте метаданные и пределы сопоставления.") }
                        review.geometryRules[geometryPlan] = rule
                        plan = nil
                        message = nil
                    } catch { message = error.localizedDescription }
                }.disabled(horizon == nil)
                Text("Укажите пределы для этого проекта и подтвердите, что отметки DXF используют датум набора.")
                    .font(.caption)
            }
        }.disabled(task != nil)
    }

    private func addRange() {
        guard let id = rangeHorizon else { return }
        do {
            let range = try RegulatorySourceImport.ElevationRange(minimum: ElevationInput.meters(minimum),
                maximum: ElevationInput.meters(maximum), datum: review.frame.verticalDatum)
            guard range.valid else { throw MappingError.invalid("Проверьте нижнюю и верхнюю отметки.") }
            review.ranges[id] = range
            plan = nil
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func compare() {
        guard task == nil, let snapshot else { return }
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
        guard task == nil, let plan else { return }
        let url = self.url
        task = Task {
            defer { task = nil }
            do {
                let work = Task.detached(priority: .userInitiated) {
                    ExchangeBaseline.hash(try await MappingExchangeFileRead.data(url: url))
                }
                let hash = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                guard hash == plan.workbookSHA256 else {
                    throw ExchangeImportError("Файл изменился после проверки. Выберите книгу снова.")
                }
                try await mapping.persist { workflow in
                    try workflow.commit(RegulatorySourceImport.applying(plan, to: workflow.committed))
                }
                self.plan = nil
                message = "Набор сохранён. Наблюдения доступны в журнале проекта."
            } catch { message = error.localizedDescription }
        }
    }
}
