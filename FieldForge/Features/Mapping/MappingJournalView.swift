import SwiftUI
import UIKit

struct MappingJournalView: View {
    @EnvironmentObject private var mapping: MappingModel
    var importedProjectID: UUID? = nil
    var importedDataset: String? = nil
    @State private var query = MappingJournalQuery()
    @State private var scope: JournalScope?
    @State private var datesEnabled = false
    @State private var fromDate = Date()
    @State private var throughDate = Date()
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var destination: SourceAssignment?
    @State private var isRematching = false
    @State private var message: String?
    private var projectID: UUID? { importedProjectID ?? mapping.workflow?.context.projectID }
    private var observations: [JournalObservation] { mapping.workflow?.committed.journalObservations(projectID: projectID) ?? [] }
    private var visible: [JournalObservation] {
        var effective = query
        effective.startDate = datesEnabled ? fromDate : nil
        effective.endDate = datesEnabled ? throughDate : nil
        return effective.journalRecords(observations, projectID: projectID)
    }
    private var horizons: [MappingHorizon] { (mapping.workflow?.journal.horizons ?? []).filter { $0.projectID == projectID } }
    private var excavations: [MappingExcavation] {
        (mapping.workflow?.journal.excavations ?? []).filter {
            $0.projectID == projectID && (query.horizonID == nil || $0.horizonIDs.contains(query.horizonID!))
        }
    }
    var body: some View {
        let visible = self.visible
        let datasets = Set(observations.compactMap(\.dataset)).sorted()
        let selectable = visible.filter { $0.dataset != nil }
        List {
            Section {
                Text(projectID.flatMap { mapping.workflow?.committed.projects[$0]?.name } ?? "Выберите проект в картировании")
                    .font(.headline)
                Button { scope = .horizon } label: {
                    LabeledContent("Горизонт", value: horizons.first { $0.id == query.horizonID }?.displayName ?? "Все горизонты")
                }.accessibilityIdentifier("journalHorizonFilter")
                Button { scope = .excavation } label: {
                    LabeledContent("Выработка", value: excavations.first { $0.id == query.excavationID }?.name ?? "Все выработки")
                }.accessibilityIdentifier("journalExcavationFilter")
                if !datasets.isEmpty {
                    Picker("Назначение горизонта", selection: $query.horizonStatus) {
                        Text("Любое").tag(JournalObservation.HorizonStatus?.none)
                        ForEach(JournalObservation.HorizonStatus.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    Picker("Набор Excel", selection: $query.dataset) {
                        Text("Все наблюдения").tag(String?.none)
                        ForEach(datasets, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                }
                Toggle("Период наблюдений", isOn: $datesEnabled).accessibilityIdentifier("journalDateFilter")
                if datesEnabled {
                    DatePicker("С", selection: $fromDate, displayedComponents: .date)
                        .onChange(of: fromDate) { _, value in if throughDate < value { throughDate = value } }
                    DatePicker("По включительно", selection: $throughDate, in: fromDate..., displayedComponents: .date)
                    Text("Даты: \(TimeZone.current.identifier)").font(.caption)
                }
                Button("Сбросить фильтры") {
                    query = MappingJournalQuery(); datesEnabled = false
                }.accessibilityIdentifier("journalClearFilters")
            }
            if let projectID, !datasets.isEmpty {
                Section("Назначение наблюдений Excel") {
                    if let dataset = query.dataset ?? (datasets.count == 1 ? datasets.first : nil) {
                        NavigationLink("Координаты набора и правила DXF") {
                            RegulatoryDatasetSetupView(projectID: projectID, dataset: dataset)
                        }
                    }
                    Button("Повторить поиск горизонтов") { rematch(projectID: projectID) }
                        .disabled(isRematching || mapping.isSaving)
                    if isRematching { ProgressView() }
                    if let message { Text(message).font(.caption) }
                    if selecting {
                        Button("Выбрать видимые · \(selectable.count)") { selection.formUnion(selectable.map(\.id)) }
                            .disabled(selectable.isEmpty)
                        Button("Назначить выбранным · \(selection.count)") {
                            destination = .init(projectID: projectID, ids: selection)
                        }.disabled(selection.isEmpty || mapping.isSaving)
                        Button("Завершить выбор") { selecting = false; selection.removeAll() }
                    } else {
                        Button("Выбрать наблюдения") { selecting = true }.disabled(selectable.isEmpty)
                    }
                }
            }
            Section("Наблюдения: \(visible.count) из \(observations.count)") {
                if visible.isEmpty { Text("Нет наблюдений по выбранным условиям").accessibilityIdentifier("journalEmpty") }
                ForEach(visible) { record in
                    if selecting && record.dataset != nil {
                        Toggle(isOn: Binding(get: { selection.contains(record.id) }, set: { checked in
                            if checked { selection.insert(record.id) } else { selection.remove(record.id) }
                        })) { observationLabel(record) }
                    } else {
                        NavigationLink { JournalObservationDetail(observation: record) } label: { observationLabel(record) }
                            .accessibilityIdentifier(record.dataset == nil ? "journalRecord-\(record.id.uuidString)" :
                                "journalSourceRecord-\(record.id.uuidString)")
                    }
                }
            }
        }.accessibilityIdentifier("journalObservations")
            .navigationTitle("Журнал проекта")
            .toolbar {
                NavigationLink { MappingExchangeImportView() } label: {
                    Label("Импорт Excel", systemImage: "square.and.arrow.down")
                }.accessibilityIdentifier("mappingExchangeImportAction")
                if let committed = mapping.workflow?.committed {
                    NavigationLink { MappingExportView(committed: committed, projectID: projectID) } label: {
                        Label("Выгрузка", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("mappingExportAction")
                }
            }
            .background(JournalSearchAccessibility(identifier: "journalPicketSearch"))
            .searchable(text: $query.picket, placement: .navigationBarDrawer(displayMode: .always), prompt: "Пикет, метры или ID Excel")
            .onChange(of: query.horizonID) { _, _ in query.excavationID = nil }
            .onChange(of: projectID) { _, _ in query = MappingJournalQuery(); datesEnabled = false; selection.removeAll() }
            .onAppear { if let importedDataset { query.dataset = importedDataset } }
            .sheet(item: $destination, onDismiss: { selection.removeAll() }) { SourceAssignmentView(assignment: $0) }
            .sheet(item: $scope) { scope in
                switch scope {
                case .horizon:
                    JournalScopeSelection(title: "Горизонт", all: "Все горизонты", searchIdentifier: "journalHorizonSearch",
                        items: horizons.map { ($0.id, $0.displayName) }, selection: $query.horizonID)
                case .excavation:
                    JournalScopeSelection(title: "Выработка", all: "Все выработки", searchIdentifier: "journalExcavationSearch",
                        items: excavations.map { ($0.id, $0.name) }, selection: $query.excavationID)
                }
            }
    }
    private func observationLabel(_ record: JournalObservation) -> some View {
        let committed = mapping.workflow?.committed
        let context = record.context
        return VStack(alignment: .leading, spacing: 6) {
            Text(context.excavationID.flatMap { committed?.excavations[$0]?.name } ?? "Выработка не назначена").font(.headline)
            Text(record.displayPicket).font(.subheadline)
            if let revision = committed?.latestRevisions[record.id] {
                Text("Версия \(revision.version) · исправлено \(MappingCorrectionDateText.format(revision.correctedAt))").font(.caption)
            }
            Text(context.horizonID.flatMap { committed?.horizons[$0]?.displayName } ?? record.horizonStatus.title)
                .font(.caption).foregroundStyle(.secondary)
            switch record {
            case .native(let point): Text(MappingDateText.compact(point)).font(.caption)
            case .source(let point): Text("Excel · \(point.key.dataset) · \(point.key.sourceID)").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }

    private func rematch(projectID: UUID) {
        let dataset = query.dataset
        let plans = mapping.planStore
        isRematching = true
        Task {
            defer { isRematching = false }
            do {
                let count = try await mapping.persist { workflow in
                    let next = try RegulatorySourceImport.rematching(projectID: projectID, dataset: dataset,
                                                                       snapshot: workflow.committed, plans: plans)
                    let before = workflow.journal.regulatorySourceObservations?.filter {
                        $0.key.projectID == projectID && $0.latest?.destination.horizonID != nil
                    }.count ?? 0
                    let after = next.regulatorySourceObservations?.filter {
                        $0.key.projectID == projectID && $0.latest?.destination.horizonID != nil
                    }.count ?? 0
                    if next != workflow.journal { try workflow.commit(next) }
                    return after - before
                }
                message = "Определено горизонтов: \(count)."
            } catch { message = error.localizedDescription }
        }
    }
}

struct JournalObservationDetail: View {
    let observation: JournalObservation
    var body: some View {
        switch observation {
        case .native(let record): MappingObservationDetail(record: record)
        case .source(let record): RegulatorySourceObservationDetail(record: record)
        }
    }
}

private enum JournalScope: String, Identifiable {
    case horizon, excavation
    var id: String { rawValue }
}

/// A searchable list avoids an unbounded flat menu for hundreds of excavations.
private struct JournalScopeSelection: View {
    let title: String
    let all: String
    let searchIdentifier: String
    let items: [(UUID, String)]
    @Binding var selection: UUID?
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Button(all) { selection = nil; dismiss() }
                ForEach(items.filter { search.isEmpty || $0.1.localizedCaseInsensitiveContains(search) }, id: \.0) { item in
                    Button { selection = item.0; dismiss() } label: {
                        HStack { Text(item.1); Spacer(); if selection == item.0 { Image(systemName: "checkmark") } }
                    }
                }
            }.accessibilityIdentifier("\(searchIdentifier)Results")
                .navigationTitle(title)
                .background(JournalSearchAccessibility(identifier: searchIdentifier))
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
                .toolbar { Button("Закрыть") { dismiss() } }
        }
    }
}

/// SwiftUI's searchable modifier does not expose the native search field's identifier.
/// Tag only this navigation controller's field, including when a filter is presented.
private struct JournalSearchAccessibility: UIViewControllerRepresentable {
    let identifier: String

    func makeUIViewController(context: Context) -> Controller { Controller(identifier: identifier) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.identifier = identifier
        controller.identifySearchField()
    }

    final class Controller: UIViewController {
        var identifier: String
        init(identifier: String) { self.identifier = identifier; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); identifySearchField() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); identifySearchField() }

        func identifySearchField() {
            navigationController?.topViewController?.navigationItem.searchController?
                .searchBar.searchTextField.accessibilityIdentifier = identifier
        }
    }
}

enum MappingDateText {
    static func compact(_ record: MappingObservation) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: record.observedUTCOffsetSeconds)
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: record.observedAt)
    }
    static func format(_ record: MappingObservation) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: record.observedUTCOffsetSeconds)
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss ZZZZZ"
        return formatter.string(from: record.observedAt)
    }
}

struct MappingObservationDetail: View {
    @EnvironmentObject private var mapping: MappingModel
    private let snapshot: MappingObservation
    let historical: Bool
    let historicalVersion: Int?
    @State private var correction: MappingCorrectionDraft?
    @State private var correctionError: String?
    init(record: MappingObservation, historical: Bool = false, historicalVersion: Int? = nil) {
        snapshot = record; self.historical = historical; self.historicalVersion = historicalVersion
    }
    private var excavationName: String { mapping.workflow?.committed.excavations[record.excavationID]?.name ?? "Выработка" }
    private var record: MappingObservation { historical ? snapshot : (mapping.workflow?.committed.observation(id: snapshot.id) ?? snapshot) }
    var body: some View {
        let record = self.record
        let measurements = mapping.workflow?.committed.measurements(for: record) ?? []
        List {
            Section {
                Text(excavationName).font(.title2.bold())
                Text(record.displayPicket).font(.subheadline)
                Text(MappingDateText.compact(record)).font(.caption).foregroundStyle(.secondary)
            }
            if historical, let historicalVersion { Text("Версия \(historicalVersion) · исторический снимок").font(.caption) }
            if !historical {
                Section {
                    Button("Редактировать наблюдение") {
                        do { correction = try mapping.workflow?.correction(for: record.id) }
                        catch { correctionError = error.localizedDescription }
                    }.accessibilityIdentifier("editMappingObservation")
                    NavigationLink("История изменений") { MappingRevisionHistory(observationID: record.id) }
                        .accessibilityIdentifier("mappingRevisionHistory")
                    if let revision = mapping.workflow?.committed.latestRevisions[record.id] {
                        Text("Версия \(revision.version) · исправлено \(MappingCorrectionDateText.format(revision.correctedAt))")
                            .font(.caption).accessibilityIdentifier("mappingRevisionBadge")
                    } else { Text("Версия 1 · исходное наблюдение").font(.caption) }
                }
            }
            Section(historical ? "Исторический снимок · только просмотр" : "Наблюдение · актуальная версия") {
                LabeledContent("Проект", value: mapping.workflow?.committed.projects[record.projectID]?.name ?? record.projectID.uuidString)
                LabeledContent("Горизонт", value: mapping.workflow?.committed.horizons[record.horizonID]?.displayName ?? record.horizonID.uuidString)
                LabeledContent("Выработка", value: mapping.workflow?.committed.excavations[record.excavationID]?.name ?? record.excavationID.uuidString)
                LabeledContent("Пикет", value: record.displayPicket)
                LabeledContent("Метры", value: EngineeringDisplay.number(record.chainageMeters))
                LabeledContent("Начало / направление", value: record.chainageOriginAndDirection == "unknown" ? "Неизвестно" : record.chainageOriginAndDirection)
                LabeledContent("Дата наблюдения", value: MappingDateText.format(record))
                Text(record.observedTimeZoneID)
            }
            Section(record.coordinates.map { MappingCoordinateText.header(xyUnits: $0.units) } ?? "Координаты") {
                if let c = record.coordinates {
                    if c.source == "regulatoryExcel" && (c.x != nil || c.y != nil) {
                        Text("XY из Excel: подтвердите систему координат и привязку к DXF для отображения на плане.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    let xyUnit = MappingCoordinateText.xyUnit(c.units)
                    LabeledContent(c.units == "m" ? "X" : "X, \(xyUnit)", value: c.x.map { EngineeringDisplay.coordinate($0) } ?? "Неизвестно")
                    LabeledContent(c.units == "m" ? "Y" : "Y, \(xyUnit)", value: c.y.map { EngineeringDisplay.coordinate($0) } ?? "Неизвестно")
                    LabeledContent(c.units == "m" ? "Z" : "Z, м", value: c.z.map { EngineeringDisplay.coordinate($0) } ?? "Неизвестно")
                    DisclosureGroup("Полная точность координат") {
                        Text("X \(c.x.map(ElevationInput.text) ?? "—") · Y \(c.y.map(ElevationInput.text) ?? "—") · Z \(c.z.map(ElevationInput.text) ?? "—")")
                            .font(.caption).textSelection(.enabled)
                    }
                    LabeledContent("СК", value: c.crs); LabeledContent("Оси / высоты", value: c.axes)
                    Text(c.provenance)
                    LabeledContent("Источник Z", value: c.zPlanGeometry?.sourceLabel ?? c.zOrigin?.title ?? "Не указан в исходной записи")
                    if let geometry = c.zPlanGeometry {
                        DisclosureGroup("Стены — источники Z") { Text(geometry.sourceDetails).font(.caption) }
                    }
                    if let level = c.zHorizonElevation { Text("Исходная отметка: \(ElevationInput.label(level)); система: \(c.zDatum ?? "unknown")") }
                    DisclosureGroup("Полная точность координат") {
                        LabeledContent("X", value: c.x.map { CSVExporter.engineeringNumber($0) } ?? "Неизвестно")
                        LabeledContent("Y", value: c.y.map { CSVExporter.engineeringNumber($0) } ?? "Неизвестно")
                        LabeledContent("Z", value: c.z.map { CSVExporter.engineeringNumber($0) } ?? "Неизвестно")
                    }.font(.caption).textSelection(.enabled)
                } else { Text("Координаты не заданы") }
            }
            if let rock = record.rock { Section("Литология") { LabeledContent("ROCK", value: rock.code); if let name = rock.name { Text(name) } } }
            if !historical { ObservationPhotosSection(pointID: record.id) }
            Section("Исходные замеры: \(record.measurementIDs.count)") {
                ForEach(measurements) { reading in
                    NavigationLink { MeasurementDetailView(record: reading) } label: { MeasurementSummary(reading: reading) }
                        .accessibilityIdentifier("pointMeasurement-\(reading.id.uuidString)")
                }
                if record.measurementIDs.isEmpty { Text("Замеры не добавлены") }
            }
            if let geology = record.geology {
                MappingGeologyDetail(geology: geology, measurements: measurements)
            }
            MappingRatingsDetail(ratings: record.ratings)
            Section("Примечания") { Text(record.notes.isEmpty ? "Нет примечаний" : record.notes) }
            Section("Метаданные") {
                LabeledContent("Создано", value: MeasurementDateText.format(record.createdAt, detailed: true))
                Text(record.id.uuidString).textSelection(.enabled)
                Text("UUID точки постоянный. Дата полевого наблюдения и время исправления хранятся отдельно. Исходные замеры неизменяемы.")
            }.font(.caption)
        }.navigationTitle(excavationName).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $correction) { draft in MappingCorrectionEditor(draft: draft) }
            .alert("Исправление", isPresented: Binding(get: { correctionError != nil }, set: { if !$0 { correctionError = nil } })) {
                Button("Понятно", role: .cancel) { correctionError = nil }
            } message: { Text(correctionError ?? "") }
    }
}


enum MappingCorrectionDateText {
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = .current; formatter.dateFormat = "dd.MM.yyyy HH:mm:ss.SSS ZZZZZ"
        return formatter.string(from: date)
    }
}

private struct SourceAssignment: Identifiable {
    let id = UUID()
    let projectID: UUID
    let ids: Set<UUID>
    var current: MappingContext? = nil
}

private struct SourceAssignmentView: View {
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    let assignment: SourceAssignment
    @State private var horizon: UUID?
    @State private var excavation: UUID?
    @State private var excavationOnly = false
    @State private var error: String?

    private var selected: [RegulatorySourceObservation] {
        assignment.ids.compactMap { mapping.workflow?.committed.sourceByID[$0] }
    }
    private var selectedHorizons: Set<UUID> { Set(selected.compactMap { $0.latest?.destination.horizonID }) }
    private var allHaveHorizons: Bool { !selected.isEmpty && selected.allSatisfy { $0.latest?.destination.horizonID != nil } }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Назначить", selection: $excavationOnly) {
                    Text("Горизонт и выработку").tag(false)
                    Text("Только выработку").tag(true)
                }.onChange(of: excavationOnly) { _, _ in excavation = nil }
                if !excavationOnly {
                    Picker("Горизонт", selection: $horizon) {
                        Text("Без горизонта").tag(UUID?.none)
                        ForEach((mapping.workflow?.journal.horizons ?? []).filter { $0.projectID == assignment.projectID }) {
                            Text($0.displayName).tag(Optional($0.id))
                        }
                    }.onChange(of: horizon) { _, _ in excavation = nil }
                }
                let requiredHorizons = excavationOnly ? selectedHorizons : Set([horizon].compactMap { $0 })
                Picker("Выработка", selection: $excavation) {
                    Text("Без выработки").tag(UUID?.none)
                    ForEach((mapping.workflow?.journal.excavations ?? []).filter {
                        $0.projectID == assignment.projectID && !requiredHorizons.isEmpty && requiredHorizons.isSubset(of: $0.horizonIDs)
                    }) { Text($0.name).tag(Optional($0.id)) }
                }
                if excavationOnly && !allHaveHorizons { Text("Сначала назначьте горизонт всем выбранным точкам.") }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Назначение · \(assignment.ids.count)")
                .onAppear { horizon = assignment.current?.horizonID; excavation = assignment.current?.excavationID }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") { save() }.disabled(mapping.isSaving || (excavationOnly && !allHaveHorizons))
                    }
                }
        }
    }

    private func save() {
        let ids = assignment.ids
        let context = MappingContext(projectID: assignment.projectID, horizonID: horizon, excavationID: excavation)
        let onlyExcavation = excavationOnly
        let projectID = assignment.projectID
        Task {
            do {
                try await mapping.persist { workflow in
                    let next = try onlyExcavation
                        ? RegulatorySourceImport.assigningExcavation(context.excavationID, ids: ids, projectID: projectID, journal: workflow.journal)
                        : RegulatorySourceImport.assigning(ids, destination: context, journal: workflow.journal)
                    if next != workflow.journal { try workflow.commit(next) }
                }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct RegulatorySourceObservationDetail: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var editing: RegulatorySourceObservation?
    @State private var assignment: SourceAssignment?
    private let snapshot: RegulatorySourceObservation
    init(record: RegulatorySourceObservation) { snapshot = record }
    private var record: RegulatorySourceObservation {
        mapping.workflow?.committed.sourceByID[snapshot.id] ?? snapshot
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Набор", value: record.key.dataset)
                LabeledContent("Исходный ID", value: record.key.sourceID)
                LabeledContent("UUID", value: record.id.uuidString)
                Button("Исправить геологические данные") { editing = record }.disabled(mapping.isSaving)
            }
            if let version = record.latest {
                let point = JournalObservation.source(record)
                let committed = mapping.workflow?.committed
                Section("Расположение") {
                    LabeledContent("Горизонт", value: point.context.horizonID.flatMap { committed?.horizons[$0]?.displayName } ?? "Не назначен")
                    LabeledContent("Выработка", value: point.context.excavationID.flatMap { committed?.excavations[$0]?.name } ?? "Не назначена")
                    Text(point.horizonStatus.title)
                    if let issue = version.matchingIssue { Text(issue.title).font(.caption) }
                    if let reason = committed?.sourceDisplayIssue(record) { Label(reason, systemImage: "map").font(.caption) }
                    Button("Назначить горизонт или выработку") {
                        assignment = .init(projectID: record.key.projectID, ids: [record.id], current: point.context)
                    }.disabled(mapping.isSaving)
                    NavigationLink("Координаты набора и правила DXF") {
                        RegulatoryDatasetSetupView(projectID: record.key.projectID, dataset: record.key.dataset)
                    }
                }
                Section("Координаты") {
                    ForEach(Array(zip(["X", "Y", "Z, м"], version.cells[2...4])), id: \.0) { label, value in
                        LabeledContent(label, value: value.isEmpty ? "Неизвестно" : value).textSelection(.enabled)
                    }
                    if let coordinates = point.coordinates {
                        LabeledContent("Единицы XY", value: coordinates.units.isEmpty ? "Неизвестны" : MappingCoordinateText.xyUnit(coordinates.units))
                    }
                }
            }
            ForEach(record.versions.indices.reversed(), id: \.self) { index in
                let version = record.versions[index]
                DisclosureGroup("Версия \(index + 1) · строка \(version.sourceRow)") {
                    LabeledContent("Сохранено", value: version.savedAt.formatted())
                    LabeledContent("Источник версии", value: versionOrigin(version))
                    LabeledContent("Север", value: version.northReference.title)
                    if let issue = version.matchingIssue { Text(issue.title) }
                    switch version.resolution {
                    case .geometry(let id, let hash, let rule):
                        LabeledContent("Ревизия DXF", value: mapping.workflow?.committed.plan(id: id)?.version ?? id.uuidString)
                        LabeledContent("SHA-256 DXF", value: hash)
                        LabeledContent("Допуски XY / Z, м", value: "\(rule.maximumXYMeters) / \(rule.maximumZMeters)")
                        if let evidence = version.geometryEvidence {
                            LabeledContent("Сегмент", value: evidence.segment.handle ?? "#\(evidence.segment.entityOrdinal)")
                            LabeledContent("Z сегмента, м", value: ElevationInput.text(evidence.projectedZMeters))
                            LabeledContent("Расхождения XY / Z, м", value: "\(evidence.xyDistanceMeters) / \(evidence.zDifferenceMeters)")
                        }
                    case .elevationRange(let range):
                        LabeledContent("Подтверждённый диапазон Z, м", value: "\(range.minimum)…\(range.maximum)")
                    case .retained: Text("Сохранён прежний горизонт; исходное подтверждение см. в истории.")
                    case nil: EmptyView()
                    }
                    LabeledContent("SHA-256 книги", value: version.workbookSHA256)
                    LabeledContent("Датум Z", value: version.frame.verticalDatum.isEmpty ? "Неизвестен" : version.frame.verticalDatum)
                    LabeledContent("Система координат XY", value: version.frame.crs.isEmpty ? "Неизвестна" : version.frame.crs)
                    LabeledContent("Оси XY", value: version.frame.axes.isEmpty ? "Неизвестны" : version.frame.axes)
                    LabeledContent("Единицы XY", value: version.frame.xyUnits.isEmpty ? "Неизвестны" : MappingCoordinateText.xyUnit(version.frame.xyUnits))
                    LabeledContent("X источника", value: version.cells[2].isEmpty ? "Не указана" : version.cells[2])
                    LabeledContent("Y источника", value: version.cells[3].isEmpty ? "Не указана" : version.cells[3])
                    LabeledContent("Z источника, м", value: version.cells[4].isEmpty ? "Не указана" : version.cells[4])
                }
                Section(index == record.versions.count - 1 ? "Текущие геологические данные" : "Геологические данные версии") {
                    sourceField(version, 5, "Литология (ROCK)")
                    sourceField(version, 6, "Выветривание (A45)")
                    sourceField(version, 7, "Обводнённость (JW)")
                    sourceField(version, 8, "Категория прочности (A1)")
                    sourceField(version, 9, "UCS, МПа")
                    sourceField(version, 10, "RQD, %")
                    sourceField(version, 11, "Системы трещин (JN)")
                    sourceField(version, 12, "Шероховатость (JR)")
                    sourceField(version, 13, "Заполнитель (JA)")
                    sourceField(version, 14, "SD, м · сводное значение источника")
                    sourceField(version, 15, "Раскрытие трещин (A43)")
                    sourceField(version, 16, "Свойства трещин (JCON76)")
                    sourceField(version, 17, "Длина трещин (A42)")
                    sourceField(version, 18, "Разлом · угол падения")
                    sourceField(version, 19, "Разлом · азимут падения")
                    sourceField(version, 20, "Разлом · мощность, м")
                    ForEach(0..<4, id: \.self) { index in
                        sourceField(version, 21 + index * 2, "J\(index + 1) · угол падения")
                        sourceField(version, 22 + index * 2, "J\(index + 1) · азимут (север источника не задан)")
                    }
                    if !version.cells[29].isEmpty {
                        LabeledContent("GSI в Excel · формульное поле", value: version.cells[29])
                        Text("Сохранено как исходная ячейка; не считается независимо измеренным значением.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Дата, координаты и исходные расчётные поля сохраняются в истории.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Исходное наблюдение")
            .sheet(item: $assignment) { SourceAssignmentView(assignment: $0) }
            .sheet(item: $editing) { record in
                NavigationStack { RegulatorySourceCorrectionEditor(record: record) }
            }
    }

    private func versionOrigin(_ version: RegulatorySourceObservation.Version) -> String {
        switch version.origin {
        case .sourceImport: "Импорт исходной книги"
        case .localEdit: "Правка в журнале"
        case .workbookEdit: "Правка в выгрузке Excel"
        case .assignment: "Назначение места наблюдения"
        case nil: "Архивная версия"
        }
    }

    @ViewBuilder private func sourceField(_ version: RegulatorySourceObservation.Version, _ index: Int, _ label: String) -> some View {
        let locallyEdited = version.isLocallyEdited(index)
        if !version.cells[index].isEmpty || locallyEdited {
            LabeledContent(label, value: version.cells[index].isEmpty ? "Пусто" : version.cells[index])
            if locallyEdited {
                LabeledContent("Изменено в журнале · исходное", value: version.sourceBaseline[index].isEmpty ? "Пусто" : version.sourceBaseline[index])
                    .font(.caption)
            }
        }
    }
}

private struct RegulatorySourceCorrectionEditor: View {
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    let record: RegulatorySourceObservation
    @State private var cells: [String]
    @State private var north: GeographicReference
    @State private var activeColumn: Int?
    @State private var error: String?

    init(record: RegulatorySourceObservation) {
        self.record = record
        _cells = State(initialValue: record.latest?.cells ?? [])
        _north = State(initialValue: record.latest?.northReference ?? .unknown)
    }

    var body: some View {
        Form {
            if cells.count == RegulatoryDataWorkbook.columns.count {
                RockLithologyField(rock: Binding(get: {
                    guard !cells[5].isEmpty else { return nil }
                    return RockLithology(code: cells[5], name: nil)
                }, set: { cells[5] = $0?.code ?? "" }), projectID: record.key.projectID)
                Picker("Север для азимутов этой строки", selection: $north) {
                    ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
                }
                Section {
                    ForEach(RegulatorySourceImport.editableFields.filter { $0 != 5 }, id: \.self) { column in
                        field(column)
                    }
                } header: {
                    Text("Измерения и категории Data")
                } footer: {
                    Text("Пустое поле сохраняется без значения. Смена вида севера сохраняет исходные числовые значения азимутов.")
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Исправление наблюдения")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }
                    .disabled(mapping.isSaving || (cells == record.latest?.cells && north == record.latest?.northReference))
            }
        }
    }

    @ViewBuilder private func field(_ column: Int) -> some View {
        let title = RegulatoryDataWorkbook.columns[column]
        let options = categories(column)
        if options.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(EnterpriseGeotechnicalWorkbook.headerRows[2][column] + " · " + title).font(.subheadline)
                LosslessNumericField(text: $cells[column], displayText: cells[column],
                    focused: activeColumn == column, identifier: "regulatorySourceField-\(column)",
                    placeholder: "Не указано", onFocus: { focused in
                        if focused { activeColumn = column }
                        else if activeColumn == column { activeColumn = nil }
                    }).frame(minHeight: 44)
            }
        } else {
            let selected = cells[column]
            Picker(title, selection: $cells[column]) {
                Text("Не указано").tag("")
                ForEach(options, id: \.rating) { option in
                    Text(option.title).tag(String(option.rating))
                }
                if !selected.isEmpty, !options.contains(where: { String($0.rating) == selected }) {
                    Text("Из Excel · " + selected).tag(selected)
                }
            }
        }
    }

    private func categories(_ column: Int) -> [(rating: Int, title: String)] {
        switch column {
        case 6: RegulatoryWallAlteration.allCases.map { ($0.rating, $0.selectionLabel) }
        case 8: RegulatoryStrengthBand.allCases.map { ($0.rating, $0.selectionLabel) }
        case 15: RMR89Parameter.aperture.choices(test: nil).map { ($0.rating, $0.title) }
        case 16: JCond76Category.allCases.map { ($0.rating, $0.title) }
        case 17: RMR89Parameter.persistence.choices(test: nil).map { ($0.rating, $0.title) }
        default: []
        }
    }

    private func save() {
        activeColumn = nil
        var edited = cells
        for column in RegulatorySourceImport.editableFields where edited[column] != record.latest?.cells[column] {
            edited[column] = edited[column].trimmingCharacters(in: .whitespacesAndNewlines)
            if column != 5 { edited[column] = edited[column].replacingOccurrences(of: ",", with: ".") }
        }
        let fields = edited
        let reference = north == record.latest?.northReference ? nil : north
        Task {
            do {
                try await mapping.persist { workflow in
                    try workflow.commit(RegulatorySourceImport.editing(record, fields: fields, journal: workflow.journal, north: reference))
                }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
