import SwiftUI

@MainActor final class MappingModel: ObservableObject {
    @Published var workflow: MappingWorkflow?
    @Published var error: String?
    @Published var success = false
    private(set) var planStore: ManagedPlanStore?
    init() {
        do {
            let directory = try FileMeasurementStore.applicationStore().url.deletingLastPathComponent()
            #if DEBUG
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            #else
            let testing = false
            #endif
            #if DEBUG && targetEnvironment(simulator)
            let namespace = ProcessInfo.processInfo.environment["FIELD_FORGE_TEST_RUN_ID"].flatMap(UUID.init(uuidString:)).map { "-" + $0.uuidString } ?? ""
            #else
            let namespace = ""
            #endif
            planStore = ManagedPlanStore(root: directory.appendingPathComponent(testing ? "ui-testing-plans\(namespace)" : "plans"))
            workflow = try MappingWorkflow(store: FileMappingStore(url: directory.appendingPathComponent(testing ? "ui-testing-mapping\(namespace).json" : "mapping-v1.json")))
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
    @State private var showPlans = false
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
        .sheet(isPresented: $showPlans) {
            NavigationStack {
                HorizonPlansView(selecting: true, onSelection: { showPlans = false })
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Вернуться") { showPlans = false } } }
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
                selector("Горизонт", id: "horizonPicker", values: w.horizons.map { ($0.id, $0.displayName) }, selection: context(\.horizonID), kind: .horizon)
                selector("Выработка", id: "excavationPicker", values: w.excavations.map { ($0.id, $0.name) }, selection: context(\.excavationID), kind: .excavation)
            }.padding(.horizontal).padding(.vertical, 6).background(.bar)
            Form {
                Section("Пикет и дата") {
                    TextField("Пикет: ПК 0+005 или метры", text: draft(\.picket, fallback: ""))
                        .accessibilityIdentifier("mappingPicket").focused($focused)
                    DatePicker("Дата наблюдения", selection: Binding(get: { mapping.workflow?.draft.observedAtOverride ?? Date() },
                        set: { value in mapping.perform { $0.draft.observedAtOverride = value } }))
                        .accessibilityIdentifier("mappingDate")
                }
                Section {
                    coordinate("X", \.x); coordinate("Y", \.y); coordinate("Z", \.z)
                    Button("Выбрать на плане", systemImage: "map") { focused = false; showPlans = true }
                        .disabled(w.context.horizonID == nil).accessibilityIdentifier("selectHorizonPlan")
                } header: { Text(MappingCoordinateText.header(xyUnits: w.draft.xyUnits)) } footer: {
                    Text(w.draft.zOrigin == .horizonDefault ? "Z: по горизонту · номинальная отметка, не съёмка" : "Z: ручной ввод или неизвестно · метры")
                }
                Section("Измерения") {
                    NavigationLink("Открыть независимое измерение", destination: MeasurementView())
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
            Text(name == "Z" && mapping.workflow?.draft.xyUnits != "m" ? "Z, м" : name).frame(width: 42, alignment: .leading)
            TextField("Неизвестно", text: draft(key, fallback: "")).keyboardType(.numbersAndPunctuation)
                .focused($focused).accessibilityIdentifier("mapping\(name)")
        }
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
    @FocusState private var inputFocused: Bool
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
                    if kind == .horizon {
                        TextField("Отметка горизонта, м", text: $elevation).keyboardType(.numbersAndPunctuation).focused($inputFocused)
                            .accessibilityIdentifier("contextElevation")
                        if editingID != nil { Text("Исходное название: \(name)").font(.caption) }
                    } else { TextField("Название", text: $name).focused($inputFocused).accessibilityIdentifier("contextName") }
                    if kind == .excavation {
                        Text("Одна выработка может относиться к нескольким горизонтам.").font(.caption)
                        ForEach(mapping.workflow?.horizons ?? []) { horizon in
                            Toggle(horizon.displayName, isOn: Binding(get: { horizonIDs.contains(horizon.id) }, set: { on in
                                if on { horizonIDs.insert(horizon.id) } else { horizonIDs.remove(horizon.id) }
                            }))
                        }
                    }
                    Button(editingID == nil ? "Создать" : "Сохранить изменения") { save() }
                        .accessibilityIdentifier("saveContext")
                    if editingID != nil { Button("Новая запись") { editingID = nil; name = ""; elevation = ""; datum = "неизвестно"; error = nil } }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if kind == .horizon, editingID != nil {
                    Section {
                        NavigationLink("Высотная система · необязательно") {
                            Form {
                                TextField("Высотная система", text: $datum)
                                Text("Метаданные применятся после сохранения горизонта. Исходные наблюдения сохраняют прежние значения.").font(.caption)
                            }.navigationTitle("Высотная система")
                        }
                    }
                }
            }.navigationTitle(kind.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { inputFocused = false } }
                }
                .onAppear { if let id = mapping.workflow?.context.horizonID { horizonIDs = [id] } }
        }
    }
    private var entries: [(UUID, String)] {
        guard let w = mapping.workflow else { return [] }
        switch kind {
        case .project: return w.journal.projects.map { ($0.id, $0.name) }
        case .horizon: return w.horizons.map { ($0.id, $0.displayName) }
        case .excavation: return w.journal.excavations.filter { $0.projectID == w.context.projectID }.map { ($0.id, $0.name) }
        }
    }
    private func load(_ id: UUID) {
        editingID = id; name = entries.first { $0.0 == id }?.1 ?? ""
        if let h = mapping.workflow?.journal.horizons.first(where: { $0.id == id }) {
            name = h.name; elevation = h.elevationMeters.map { ElevationInput.text($0) } ?? ""; datum = h.elevationDatum
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
                if let editingID { try mapping.workflow!.updateHorizon(id: editingID, elevation: elevation, datum: datum) }
                else { try mapping.workflow!.createHorizon(elevation: elevation, datum: datum) }
            case .excavation:
                if let editingID { try mapping.workflow!.updateExcavation(id: editingID, name: name, horizonIDs: horizonIDs) }
                else { try mapping.workflow!.createExcavation(name: name, horizonIDs: horizonIDs) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
