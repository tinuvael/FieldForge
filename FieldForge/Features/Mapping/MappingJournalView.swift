import SwiftUI
import UIKit

struct MappingJournalView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var query = MappingJournalQuery()
    @State private var scope: JournalScope?
    @State private var datesEnabled = false
    @State private var fromDate = Date()
    @State private var throughDate = Date()
    private var projectID: UUID? { mapping.workflow?.context.projectID }
    private var observations: [MappingObservation] {
        var effective = query
        effective.startDate = datesEnabled ? fromDate : nil
        effective.endDate = datesEnabled ? throughDate : nil
        return effective.apply(mapping.workflow?.journal.effectiveObservations ?? [], projectID: projectID)
    }
    private var horizons: [MappingHorizon] { mapping.workflow?.horizons ?? [] }
    private var excavations: [MappingExcavation] {
        (mapping.workflow?.journal.excavations ?? []).filter {
            $0.projectID == projectID && (query.horizonID == nil || $0.horizonIDs.contains(query.horizonID!))
        }
    }
    var body: some View {
        List {
            Section {
                Text(mapping.workflow?.journal.projects.first { $0.id == projectID }?.name ?? "Выберите проект в картировании")
                    .font(.headline)
                Button { scope = .horizon } label: {
                    LabeledContent("Горизонт", value: horizons.first { $0.id == query.horizonID }?.displayName ?? "Все горизонты")
                }.accessibilityIdentifier("journalHorizonFilter")
                Button { scope = .excavation } label: {
                    LabeledContent("Выработка", value: excavations.first { $0.id == query.excavationID }?.name ?? "Все выработки")
                }.accessibilityIdentifier("journalExcavationFilter")
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
            Section("Наблюдения: \(observations.count) из \(mapping.workflow?.observations.count ?? 0)") {
                if observations.isEmpty { Text("Нет наблюдений по выбранным условиям").accessibilityIdentifier("journalEmpty") }
                ForEach(observations) { record in
                    NavigationLink { MappingObservationDetail(record: record) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name(excavation: record.excavationID)).font(.headline)
                            Text(record.displayPicket).font(.subheadline)
                            if let revision = mapping.workflow?.journal.history(for: record.id).last {
                                Text("Версия \(revision.version) · исправлено \(MappingCorrectionDateText.format(revision.correctedAt))").font(.caption)
                            }
                            Text("\(MappingDateText.compact(record)) · \(name(horizon: record.horizonID))").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("journalRecord-\(record.id.uuidString)")
                }
            }
        }.accessibilityIdentifier("journalObservations")
            .navigationTitle("Журнал проекта")
            .toolbar {
                if let journal = mapping.workflow?.journal {
                    NavigationLink { MappingExportView(journal: journal, projectID: projectID) } label: {
                        Label("Выгрузка", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("mappingExportAction")
                }
            }
            .background(JournalSearchAccessibility(identifier: "journalPicketSearch"))
            .searchable(text: $query.picket, placement: .navigationBarDrawer(displayMode: .always), prompt: "Пикет или метры")
            .onChange(of: query.horizonID) { _, _ in query.excavationID = nil }
            .onChange(of: projectID) { _, _ in query = MappingJournalQuery(); datesEnabled = false }
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
    private func name(horizon: UUID) -> String { mapping.workflow?.journal.horizons.first { $0.id == horizon }?.displayName ?? horizon.uuidString }
    private func name(excavation: UUID) -> String { mapping.workflow?.journal.excavations.first { $0.id == excavation }?.name ?? excavation.uuidString }
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
    private var excavationName: String { mapping.workflow?.journal.excavations.first { $0.id == record.excavationID }?.name ?? "Выработка" }
    private var record: MappingObservation { historical ? snapshot : (mapping.workflow?.journal.effectiveObservation(id: snapshot.id) ?? snapshot) }
    var body: some View {
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
                    if let revision = mapping.workflow?.journal.history(for: record.id).last {
                        Text("Версия \(revision.version) · исправлено \(MappingCorrectionDateText.format(revision.correctedAt))")
                            .font(.caption).accessibilityIdentifier("mappingRevisionBadge")
                    } else { Text("Версия 1 · исходное наблюдение").font(.caption) }
                }
            }
            Section(historical ? "Исторический снимок · только просмотр" : "Наблюдение · актуальная версия") {
                LabeledContent("Проект", value: mapping.workflow?.journal.projects.first { $0.id == record.projectID }?.name ?? record.projectID.uuidString)
                LabeledContent("Горизонт", value: mapping.workflow?.journal.horizons.first { $0.id == record.horizonID }?.displayName ?? record.horizonID.uuidString)
                LabeledContent("Выработка", value: mapping.workflow?.journal.excavations.first { $0.id == record.excavationID }?.name ?? record.excavationID.uuidString)
                LabeledContent("Пикет", value: record.displayPicket)
                LabeledContent("Метры", value: EngineeringDisplay.number(record.chainageMeters))
                LabeledContent("Начало / направление", value: record.chainageOriginAndDirection == "unknown" ? "Неизвестно" : record.chainageOriginAndDirection)
                LabeledContent("Дата наблюдения", value: MappingDateText.format(record))
                Text(record.observedTimeZoneID)
            }
            Section(record.coordinates.map { MappingCoordinateText.header(xyUnits: $0.units) } ?? "Координаты") {
                if let c = record.coordinates {
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
                    LabeledContent("Источник Z", value: c.zOrigin == .horizonDefault ? "По горизонту · не съёмка" : c.zOrigin == .manualOverride ? "Ручное значение" : "Не указан в исходной записи")
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
                ForEach(mapping.workflow?.journal.measurements(for: record) ?? []) { reading in
                    NavigationLink { MeasurementDetailView(record: reading) } label: { MeasurementSummary(reading: reading) }
                        .accessibilityIdentifier("pointMeasurement-\(reading.id.uuidString)")
                }
                if record.measurementIDs.isEmpty { Text("Замеры не добавлены") }
            }
            if let geology = record.geology {
                MappingGeologyDetail(geology: geology, measurements: mapping.workflow?.journal.measurements(for: record) ?? [])
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
