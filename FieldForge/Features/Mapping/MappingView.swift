import SwiftUI

@MainActor final class MappingModel: ObservableObject {
    @Published var workflow: MappingWorkflow?
    @Published var error: String?
    @Published var success = false
    init() {
        do {
            let directory = try FileMeasurementStore.applicationStore().url.deletingLastPathComponent()
            #if DEBUG
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            #else
            let testing = false
            #endif
            workflow = try MappingWorkflow(store: FileMappingStore(url: directory.appendingPathComponent(testing ? "ui-testing-mapping.json" : "mapping-v1.json")))
        } catch { self.error = "Не удалось открыть картирование. Запись заблокирована: \(error.localizedDescription)" }
    }
    func perform(_ action: (inout MappingWorkflow) throws -> Void) {
        guard workflow != nil else { return }
        do { try action(&workflow!) } catch { self.error = error.localizedDescription }
    }
}

struct MappingView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var editor: ContextEditorKind?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Group {
                if let workflow = mapping.workflow {
                    capture(workflow)
                } else {
                    ContentUnavailableView("Журнал недоступен", systemImage: "exclamationmark.triangle",
                                           description: Text("Исходные данные сохранены. Проверьте файл журнала перед повторным запуском."))
                }
            }
            .navigationTitle("Картирование")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { MappingJournalView() } label: { Label("Журнал", systemImage: "book.closed") }
                        .accessibilityIdentifier("mappingJournal")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink("Измерение", destination: MeasurementView())
                        NavigationLink("Неназначенные измерения", destination: JournalView())
                        NavigationLink("Настройки", destination: SettingsView())
                    } label: { Label("Сервисы", systemImage: "ellipsis.circle") }.accessibilityIdentifier("mappingServices")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false } }
            }
        }
        .sheet(item: $editor) { kind in ContextEditor(kind: kind) }
        .alert("Картирование", isPresented: Binding(get: { mapping.error != nil }, set: { if !$0 { mapping.error = nil } })) {
            Button("Понятно", role: .cancel) { mapping.error = nil }
        } message: { Text(mapping.error ?? "") }
        .alert("Наблюдение сохранено", isPresented: $mapping.success) { Button("Продолжить", role: .cancel) {} }
        .alert("Удалить несохранённый черновик и изменить контекст?", isPresented: Binding(
            get: { mapping.workflow?.pendingContext != nil },
            set: { if !$0 { mapping.perform { $0.cancelContextChange() } } })) {
                Button("Удалить черновик", role: .destructive) { mapping.perform { try $0.confirmDiscard() } }
                Button("Остаться", role: .cancel) { mapping.perform { $0.cancelContextChange() } }
            } message: { Text("Пикет, дата, координаты и примечания ещё не сохранены.") }
    }
    private func draft<T>(_ key: WritableKeyPath<MappingDraft, T>, fallback: T) -> Binding<T> {
        Binding(get: { mapping.workflow?.draft[keyPath: key] ?? fallback },
                set: { value in mapping.perform { $0.draft[keyPath: key] = value } })
    }
    private func context(_ key: WritableKeyPath<MappingContext, UUID?>) -> Binding<UUID?> {
        Binding(get: { mapping.workflow?.context[keyPath: key] }, set: { value in
            mapping.perform { workflow in
                var next = workflow.context; next[keyPath: key] = value
                if key == \MappingContext.projectID { next.horizonID = nil; next.excavationID = nil }
                if key == \MappingContext.horizonID { next.excavationID = nil }
                try workflow.requestContext(next)
            }
        })
    }
    private func capture(_ w: MappingWorkflow) -> some View {
        VStack(spacing: 0) {
            // Context stays outside the scrolling draft during repeated capture.
            VStack(spacing: 4) {
                selector("Проект", id: "projectPicker", values: w.journal.projects.map { ($0.id, $0.name) }, selection: context(\.projectID), kind: .project)
                selector("Горизонт", id: "horizonPicker", values: w.horizons.map { ($0.id, $0.name) }, selection: context(\.horizonID), kind: .horizon)
                selector("Выработка", id: "excavationPicker", values: w.excavations.map { ($0.id, $0.name) }, selection: context(\.excavationID), kind: .excavation)
            }.padding(.horizontal).padding(.vertical, 6).background(.bar)
            Form {
                Section("Пикет и дата") {
                    TextField("Пикет: ПК 0+005 или метры", text: draft(\.picket, fallback: ""))
                        .accessibilityIdentifier("mappingPicket").focused($focused)
                    Text("ПК км+метры: ПК 0+005 = 5 м; ПК 1+005 = 1005 м. Это не 100-метровые пикеты.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Начало и направление отсчёта")
                        TextField("Неизвестно", text: draft(\.chainageOriginAndDirection, fallback: "")).focused($focused)
                    }
                    Text("Без описания начало и направление хранятся как неизвестные.").font(.caption)
                    DatePicker("Дата наблюдения", selection: Binding(get: { mapping.workflow?.draft.observedAtOverride ?? Date() },
                        set: { value in mapping.perform { $0.draft.observedAtOverride = value } }))
                        .accessibilityIdentifier("mappingDate")
                    Text("Часовой пояс: \(w.draft.timeZoneID). Новая запись без изменения даты получает время сохранения.").font(.caption)
                }
                Section("Координаты · ручной ввод · метры") {
                    coordinate("X", \.x); coordinate("Y", \.y); coordinate("Z", \.z)
                    TextField("СК / локальная система или «неизвестно»", text: draft(\.crs, fallback: "")).focused($focused)
                        .accessibilityIdentifier("mappingCRS")
                    TextField("Направления осей и высотная система", text: draft(\.axes, fallback: "")).focused($focused)
                        .accessibilityIdentifier("mappingAxes")
                    TextField("Источник / точность / ограничения", text: draft(\.coordinateProvenance, fallback: "")).focused($focused)
                        .accessibilityIdentifier("mappingProvenance")
                    Label("Выбор точки DXF ещё не реализован", systemImage: "map").foregroundStyle(.secondary)
                    Text("X/Y/Z необязательны. Z не выводится из имени или отметки горизонта. GPS под землёй не используется.").font(.caption)
                }
                Section("Измерения") {
                    NavigationLink("Открыть независимое измерение", destination: MeasurementView())
                    Text("Датчики iPhone и геологический компас сохраняют записи в неназначенный журнал. Привязка к наблюдению запланирована в Issue #8.")
                        .font(.caption).foregroundStyle(.secondary)
                    planned("Системы трещин J1–J5")
                }
                Section("Оценки и документация") {
                    planned("Barton Q"); planned("RMR"); planned("Разломы / тектонические структуры"); planned("Фотографии")
                }
                Section("Примечания") {
                    TextField("Полевые примечания", text: draft(\.notes, fallback: ""), axis: .vertical)
                        .lineLimit(3...8).focused($focused).accessibilityIdentifier("mappingNotes")
                }
                Section {
                    Button {
                        focused = false
                        mapping.perform { _ = try $0.save(); mapping.success = true }
                    } label: {
                        Text("Сохранить наблюдение").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("saveMappingObservation")
                }
            }.scrollDismissesKeyboard(.interactively)
        }.frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
    private func coordinate(_ name: String, _ key: WritableKeyPath<MappingDraft, String>) -> some View {
        HStack {
            Text(name).frame(width: 28, alignment: .leading)
            TextField("Неизвестно", text: draft(key, fallback: "")).keyboardType(.numbersAndPunctuation)
                .focused($focused).accessibilityIdentifier("mapping\(name)")
        }
    }
    private func planned(_ title: String) -> some View {
        DisclosureGroup(title) { Text("Запланировано в следующих фазах") }.disabled(true)
    }
    private func selector(_ title: String, id: String, values: [(UUID, String)], selection: Binding<UUID?>, kind: ContextEditorKind) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Picker(title, selection: selection) {
                    Text("Не выбрано").tag(nil as UUID?)
                    ForEach(values, id: \.0) { value in Text(value.1).tag(Optional(value.0)) }
                }.labelsHidden().accessibilityIdentifier(id)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { editor = kind } label: { Image(systemName: "plus.circle").font(.title2).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Управление: \(title)").accessibilityIdentifier("manage-\(id)")
                .disabled(kind != .project && mapping.workflow?.context.projectID == nil)
        }
    }
}

enum ContextEditorKind: String, Identifiable {
    case project, horizon, excavation
    var id: String { rawValue }
    var title: String { switch self { case .project: return "Проекты"; case .horizon: return "Горизонты"; case .excavation: return "Выработки" } }
}

struct ContextEditor: View {
    let kind: ContextEditorKind
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var elevation = ""
    @State private var datum = "неизвестно"
    @State private var horizonIDs: Set<UUID> = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Существующие записи · выберите для изменения") {
                    ForEach(entries, id: \.0) { item in
                        Button(item.1) { load(item.0) }
                    }
                    if entries.isEmpty { Text("Пока нет записей") }
                }
                Section(editingID == nil ? "Создать" : "Изменить название / метаданные") {
                    TextField("Название", text: $name).accessibilityIdentifier("contextName")
                    if kind == .horizon {
                        TextField("Отметка, м (необязательно)", text: $elevation).keyboardType(.numbersAndPunctuation)
                        TextField("Высотная система / неизвестно", text: $datum)
                    }
                    if kind == .excavation {
                        Text("Одна выработка может относиться к нескольким горизонтам.").font(.caption)
                        ForEach(mapping.workflow?.horizons ?? []) { horizon in
                            Toggle(horizon.name, isOn: Binding(get: { horizonIDs.contains(horizon.id) }, set: { on in
                                if on { horizonIDs.insert(horizon.id) } else { horizonIDs.remove(horizon.id) }
                            }))
                        }
                    }
                    Button(editingID == nil ? "Создать" : "Сохранить изменения") { save() }
                        .accessibilityIdentifier("saveContext")
                    if editingID != nil { Button("Новая запись") { editingID = nil; name = ""; elevation = "" } }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle(kind.title)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
                .onAppear { if let id = mapping.workflow?.context.horizonID { horizonIDs = [id] } }
        }
    }
    private var entries: [(UUID, String)] {
        guard let w = mapping.workflow else { return [] }
        switch kind {
        case .project: return w.journal.projects.map { ($0.id, $0.name) }
        case .horizon: return w.horizons.map { ($0.id, $0.name) }
        case .excavation: return w.journal.excavations.filter { $0.projectID == w.context.projectID }.map { ($0.id, $0.name) }
        }
    }
    private func load(_ id: UUID) {
        editingID = id; name = entries.first { $0.0 == id }?.1 ?? ""
        if let h = mapping.workflow?.journal.horizons.first(where: { $0.id == id }) {
            elevation = h.elevationMeters.map { String($0) } ?? ""; datum = h.elevationDatum
        }
        if let e = mapping.workflow?.journal.excavations.first(where: { $0.id == id }) { horizonIDs = e.horizonIDs }
    }
    private func save() {
        guard mapping.workflow != nil else { return }
        do {
            // Never select a newly created item implicitly: context changes go through the draft guard.
            switch kind {
            case .project:
                if let editingID { try mapping.workflow!.updateProject(id: editingID, name: name) }
                else { try mapping.workflow!.createProject(name: name) }
            case .horizon:
                if let editingID { try mapping.workflow!.updateHorizon(id: editingID, name: name, elevation: elevation, datum: datum) }
                else { try mapping.workflow!.createHorizon(name: name, elevation: elevation, datum: datum) }
            case .excavation:
                if let editingID { try mapping.workflow!.updateExcavation(id: editingID, name: name, horizonIDs: horizonIDs) }
                else { try mapping.workflow!.createExcavation(name: name, horizonIDs: horizonIDs) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
