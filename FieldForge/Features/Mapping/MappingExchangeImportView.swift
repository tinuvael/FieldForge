import SwiftUI
import UniformTypeIdentifiers

struct MappingExchangeImportView: View {
    @EnvironmentObject private var mapping: MappingModel
    @StateObject private var coordinator = MappingExchangePreviewCoordinator()
    @State private var picker = false
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
                Button("Выбрать книгу Excel…", systemImage: "doc.badge.plus") { picker = true }
                    .accessibilityIdentifier("exchangeSelectWorkbook")
                    .disabled(applying)
                if let selectedURL { LabeledContent("Файл", value: selectedURL.lastPathComponent) }
                if state.busy {
                    ProgressView("Проверка книги…")
                    let operationID = coordinator.operationID
                    Button("Отменить проверку", role: .cancel) { coordinator.cancel(operationID: operationID) }
                }
                if applying { ProgressView("Сохранение выбранных строк…") }
                if let message = applyError ?? state.message { Text(message).foregroundStyle(.red) }
                if state.preview == nil, let entries = mapping.workflow?.journal.importLedger?.entries,
                   entries.contains(where: { $0.operation.source.kind == .exchange && $0.outcome == .pending }) {
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
        .navigationTitle("Импорт Excel Exchange")
        .navigationBarBackButtonHidden(applying)
        .fileImporter(isPresented: $picker, allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data]) { result in
            guard coordinator.isActive, !applying else { return }
            switch result {
            case .success(let url): selectedURL = url; prepare(url)
            case .failure(let error): coordinator.selectionFailed(error)
            }
        }
        .alert("Подтвердить импорт?", isPresented: $confirming) {
            Button("Подтвердить") { confirm() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выбрано для импорта: \(selection.accepted.count). Каждая строка сохраняется отдельно. Неотмеченные новые и изменённые строки будут пропущены. Конфликтующие строки исключены из импорта.")
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
            LabeledContent("Проект", value: preview.projectName)
            LabeledContent("Выгружено", value: preview.exportedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Проверено строк наблюдений", value: String(preview.rowsProcessed))
            ForEach(MappingExchangePreview.Classification.allCases, id: \.self) { category in
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
        ForEach(MappingExchangePreview.Classification.allCases, id: \.self) { category in
            let records = preview.records.filter { $0.classification == category }
            if !records.isEmpty, category != .unchanged || records.contains(where: { $0.receipt != nil }) {
                Section(category.title) {
                    ForEach(records) { record in
                        DisclosureGroup {
                            Text(record.reason)
                            ForEach(visibleChanges(record)) { change in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(change.title).font(.subheadline.bold())
                                    LabeledContent("В выгрузке", value: change.before.isEmpty ? "Пусто" : change.before)
                                    LabeledContent("Предложено", value: change.after.isEmpty ? "Пусто" : change.after)
                                }.font(.caption)
                            }
                            if record.canApply {
                                Toggle(record.receipt?.outcome == .pending ? "Продолжить импорт" : "Принять изменение",
                                       isOn: decision(record.id, accepting: true))
                                    .disabled(!canChoose)
                            }
                            if record.receipt?.outcome == .pending {
                                Toggle("Отклонить незавершённую строку", isOn: decision(record.id, accepting: false))
                                    .disabled(!canChoose)
                            } else if record.classification == .conflict, record.receipt == nil, record.target != nil {
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
                    .disabled(!canChoose || mapping.isSaving ||
                        (selection.accepted.isEmpty && selection.rejectedPending.isEmpty && selection.rejectedConflicts.isEmpty &&
                            !preview.records.contains { $0.canApply && $0.receipt == nil }))
                Text("Изменения сохраняются только после подтверждения. Для конфликта с журналом нужна новая выгрузка.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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

    private func prepare(_ url: URL) {
        selection = .init(); report = nil; applyError = nil
        coordinator.prepare(url, work: .init(storage: mapping.storage))
    }

    private func confirm() {
        guard !applying, !coordinator.state.stale, let preview = coordinator.state.preview, let selectedURL else { return }
        applying = true
        applyError = nil
        let approved = selection
        Task {
            defer { applying = false }
            do { report = try await mapping.applyExchange(preview, url: selectedURL, selection: approved) }
            catch { applyError = error.localizedDescription }
        }
    }

    private struct DisplayChange: Identifiable {
        let id: String
        let title: String
        let before: String
        let after: String
    }

    private func visibleChanges(_ record: MappingExchangePreview.Record) -> [DisplayChange] {
        let labels = ["notes": "Примечание", "position": "Положение", "interval_start_text": "Начало интервала",
            "interval_start_m": "Начало интервала, м", "interval_end_text": "Конец интервала",
            "interval_end_m": "Конец интервала, м", "has_geology": "Геологические данные",
            "correction_reason": "Причина исправления", "correction_author": "Автор исправления",
            "spacing_m": "Расстояние, м", "persistence_m": "Протяжённость, м", "aperture_mm": "Раскрытие, мм",
            "roughness": "Шероховатость", "infill": "Заполнитель", "description": "Описание",
            "type": "Тип структуры", "thickness_m": "Мощность, м", "picket": "Пикет", "chainage_m": "Расстояние по выработке, м",
            "observed_at_utc": "Время наблюдения (UTC)", "x": "X", "y": "Y", "z_m": "Z, м",
            "rqd_text": "RQD, %", "rmr_spacing_m_text": "RMR89 · Расстояние, м",
            "jn_text": "Jn", "jr_text": "Jr", "ja_text": "Ja", "jw_text": "Jw", "srf_text": "SRF"]
        return record.changes.flatMap { change -> [DisplayChange] in
            let position = change.row.map { " · \(change.sheet), строка \($0)" } ?? ""
            if let title = labels[change.field] {
                return [DisplayChange(id: change.id, title: title + position, before: change.before, after: change.after)]
            }
            guard record.classification == .correction || record.classification == .new || record.classification == .conflict,
                  ["input_json", "rock_json"].contains(change.field) else { return [] }
            let paths: [(String, String)] = change.field == "rock_json" ? [("code", "Код породы"), ("name", "Название породы")] :
                [("lower", "GSI · Нижняя граница"), ("upper", "GSI · Верхняя граница"),
                 ("basicSelections.rqd", "RMR89 · Категория RQD"), ("basicSelections.spacing", "RMR89 · Категория расстояния")] +
                QParameter.allCases.flatMap { parameter in
                    let name = parameter.rawValue.uppercased()
                    return [("\(parameter.rawValue).category", "\(name) · Категория"), ("\(parameter.rawValue).origin", "\(name) · Способ выбора")]
                }
            func fields(_ text: String) -> [String: Any] {
                guard (try? ExchangeJSON.validate(text)) != nil else { return [:] }
                return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            }
            let before = fields(change.before), after = fields(change.after)
            func value(_ path: String, in fields: [String: Any]) -> String {
                let result = path.split(separator: ".").reduce(fields as Any?) { object, key in
                    (object as? [String: Any])?[String(key)]
                }
                if let number = result as? NSNumber { return number.stringValue }
                return result as? String ?? ""
            }
            return paths.compactMap { path, title in
                let a = value(path, in: before), b = value(path, in: after)
                return a == b ? nil : DisplayChange(id: change.id + "/" + path, title: title + position, before: a, after: b)
            }
        }
    }
}
