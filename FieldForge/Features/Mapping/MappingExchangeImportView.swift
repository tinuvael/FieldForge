import SwiftUI
import UniformTypeIdentifiers

struct MappingExchangeImportView: View {
    @EnvironmentObject private var mapping: MappingModel
    @StateObject private var coordinator = MappingExchangePreviewCoordinator()
    @State private var picker = false
    @State private var choosingManifest = false
    @State private var kind: MappingImportSource.Kind = .exchange
    @State private var manifestURL: URL?
    @State private var matches: [String: UUID] = [:]
    @State private var selectedURL: URL?
    @State private var selection = MappingExchangeImport.Selection()
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
                Button("Выбрать книгу Excel…", systemImage: "doc.badge.plus") {
                    choosingManifest = false; picker = true
                }
                    .accessibilityIdentifier("exchangeSelectWorkbook")
                    .disabled(applying)
                if let selectedURL { LabeledContent("Файл", value: selectedURL.lastPathComponent) }
                if kind == .regulatoryData, let selectedURL {
                    Button("Выбрать файл сопоставления…") { choosingManifest = true; picker = true }
                        .disabled(applying)
                    if let manifestURL {
                        LabeledContent("Сопоставление", value: manifestURL.lastPathComponent)
                        Button("Сопоставить вручную") {
                            self.manifestURL = nil; matches = [:]; prepare(selectedURL)
                        }.disabled(applying)
                    } else {
                        Text("Для каждой группы строк выберите наблюдение и проверьте значения журнала.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
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
            if let report {
                reportSection(report)
                if let selectedURL {
                    Button("Проверить эту книгу снова") { prepare(selectedURL) }.disabled(applying)
                }
            } else if let preview = state.preview {
                previewSections(preview, stale: state.stale)
            }
        }
        .navigationTitle("Импорт Excel")
        .navigationBarBackButtonHidden(applying)
        .fileImporter(isPresented: $picker, allowedContentTypes: [choosingManifest ? .json : (UTType(filenameExtension: "xlsx") ?? .data)]) { result in
            guard coordinator.isActive, !applying else { return }
            switch result {
            case .success(let url):
                matches = [:]
                if choosingManifest {
                    manifestURL = url
                    if let selectedURL { prepare(selectedURL) }
                } else {
                    manifestURL = nil; selectedURL = url; prepare(url)
                }
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
            selectedURL = nil; manifestURL = nil; matches = [:]
            selection = .init(); report = nil; applyError = nil
        }
        .onAppear { coordinator.activate(generation: mapping.workflow?.committed.generationID) }
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
            LabeledContent("Проверено строк наблюдений", value: String(preview.rowsProcessed))
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
                Text("Защищённые данные книги изменены. Исправьте ошибки или выгрузите новую книгу.")
                    .foregroundStyle(.orange)
            }
        }
        ForEach(categories, id: \.self) { category in
            let records = preview.records.filter { $0.classification == category }
            if !records.isEmpty, category != .unchanged || records.contains(where: { $0.receipt != nil || !$0.candidates.isEmpty }) {
                Section(category.title) {
                    ForEach(records) { record in
                        DisclosureGroup {
                            Text(record.reason)
                            if !record.candidates.isEmpty {
                                Picker("Наблюдение", selection: match(record)) {
                                    Text("Выберите наблюдение").tag(UUID?.none)
                                    ForEach(record.candidates) { candidate in
                                        Text(candidate.label).tag(Optional(candidate.id))
                                    }
                                }.disabled(!canChoose)
                            }
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
                Button("Проверить выбор и подтвердить", systemImage: "checkmark.circle") { confirming = true }
                    .disabled(!canConfirm(preview, stale: stale))
                Text("Изменения сохраняются только после подтверждения. Для конфликта с журналом нужна новая выгрузка.")
                    .font(.caption).foregroundStyle(.secondary)
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

    private func match(_ record: MappingExchangePreview.Record) -> Binding<UUID?> {
        Binding(get: { matches[record.id] }, set: { id in
            matches[record.id] = id
            if let selectedURL { prepare(selectedURL) }
        })
    }

    private func prepare(_ url: URL) {
        selection = .init(); report = nil; applyError = nil
        coordinator.prepare(url, work: .init(storage: mapping.storage, kind: kind, manifestURL: manifestURL, matches: matches))
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
