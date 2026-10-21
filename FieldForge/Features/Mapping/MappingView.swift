import SwiftUI


struct MappingView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var editor: ContextEditorKind?
    @State private var geologyEditor: MappingGeologyEditorRequest?
    @State private var showDistance = false
    @State private var lastDistance: DistanceResult?
    @State private var planSelection: MappingPlanSelectionRequest?
    @State private var choosingExcavation = false
    @FocusState private var focused: Bool
    @State private var coordinateFocus: String?
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
                    Button("Замерить расстояние", systemImage: "ruler") {
                        focused = false; lastDistance = nil; showDistance = true
                    }.accessibilityIdentifier("mappingDistance")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let lastDistance { Text("Приблизительно: \(lastDistance.text) · не сохранено") }

                        NavigationLink("Настройки", destination: SettingsView())
                    } label: { Label("Сервисы", systemImage: "ellipsis.circle") }.accessibilityIdentifier("mappingServices")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false; coordinateFocus = nil } }
            }
        }
        .fullScreenCover(isPresented: $showDistance) {
            DistanceMeasurementSheet { lastDistance = $0 }
        }
        .sheet(item: $planSelection) { request in
            NavigationStack {
                HorizonPlanLoader(plan: request.plan, selecting: true, onSelection: { planSelection = nil },
                    onPointSelection: { point, _ in
                        guard mapping.workflow != nil else { throw StorageError.writesBlocked }
                        try mapping.workflow!.selectPlanPoint(point, request: request)
                    })
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Вернуться") { planSelection = nil } } }
            }.id(request.id)
        }
        .onChange(of: mapping.workflow?.draft.id) { _, _ in planSelection = nil; geologyEditor = nil }
        .onChange(of: mapping.workflow?.context) { _, _ in planSelection = nil; geologyEditor = nil }
        .sheet(item: $geologyEditor) { request in MappingGeologyCaptureSheet(request: request) }
        .sheet(item: $editor) { kind in ContextEditor(kind: kind) }
        .sheet(isPresented: $choosingExcavation) {
            ExcavationSelectionView(selection: context(\.excavationID))
        }
        .alert("Картирование", isPresented: Binding(get: { mapping.error != nil }, set: { if !$0 { mapping.error = nil } })) {
            Button("Понятно", role: .cancel) { mapping.error = nil }
        } message: { Text(mapping.error ?? "") }
        .alert("Наблюдение сохранено", isPresented: $mapping.success) { Button("Продолжить", role: .cancel) {} }
        .alert("Отложить черновик и перейти?", isPresented: Binding(
            get: { mapping.workflow?.pendingContext != nil },
            set: { if !$0 { mapping.perform { $0.cancelContextChange() } } })) {
                Button("Отложить и перейти") { mapping.perform { try $0.preserveAndSwitch() } }
                Button("Остаться", role: .cancel) { mapping.perform { $0.cancelContextChange() } }
            } message: { Text("Вернитесь в этот проект и горизонт, чтобы продолжить. Черновик и фотографии сохраняются в памяти до закрытия приложения.") }
    }
    private func draft<T>(_ key: WritableKeyPath<MappingDraft, T>, fallback: T) -> Binding<T> {
        Binding(get: { mapping.workflow?.draft[keyPath: key] ?? fallback },
                set: { value in mapping.perform { $0.draft[keyPath: key] = value } })
    }
    private func context(_ key: WritableKeyPath<MappingContext, UUID?>) -> Binding<UUID?> {
        Binding(get: { mapping.workflow?.context[keyPath: key] }, set: { value in
            mapping.perform { workflow in
                guard workflow.context[keyPath: key] != value else { return }
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
                HStack {
                    Button { focused = false; choosingExcavation = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Выработка").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text(w.excavations.first { $0.id == w.context.excavationID }?.name ?? "Не выбрано")
                                    .font(.body).lineLimit(2)
                                Image(systemName: "chevron.up.chevron.down").font(.caption)
                            }
                            .frame(minHeight: 44)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("excavationPicker")
                    Button { focused = false; editor = .excavation } label: {
                        Image(systemName: "plus.circle").font(.title2).frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Управление: Выработка").accessibilityIdentifier("manage-excavationPicker").disabled(w.context.projectID == nil)
                }
            }.padding(.horizontal).padding(.vertical, 6).background(.bar)
            Form {
                Section("Пикет и дата") {
                    TextField("Пикет: 12,18 или 12+1,8", text: draft(\.picket, fallback: ""))
                        .keyboardType(.numbersAndPunctuation).accessibilityIdentifier("mappingPicket").focused($focused)
                    if let confirmation = FieldPicketInput.confirmation(w.draft.picket) {
                        Text(confirmation).font(.caption).foregroundStyle(.secondary)
                    }
                    DatePicker("Дата наблюдения", selection: Binding(get: { mapping.workflow?.draft.observedAtOverride ?? Date() },
                        set: { value in mapping.perform { $0.draft.observedAtOverride = value } }))
                        .accessibilityIdentifier("mappingDate")
                }
                Section {
                    coordinate("X", \.x); coordinate("Y", \.y); coordinate("Z", \.z)
                    Button("Выбрать на плане", systemImage: "map") {
                        focused = false; coordinateFocus = nil
                        do { planSelection = try mapping.beginCoordinateSelection() }
                        catch { mapping.error = error.localizedDescription }
                    }
                        .disabled(w.context.horizonID == nil).accessibilityIdentifier("selectHorizonPlan")
                } header: { Text("Координаты") }
                MappingJointSetsSection { geologyEditor = $0 }
                MappingRatingsForm(q: draft(\.bartonQ, fallback: BartonQInput()),
                                   rmr: draft(\.rmr89, fallback: RMR89Input()), focus: $focused)
                Section("Примечания") {
                    TextField("Полевые примечания", text: draft(\.notes, fallback: ""), axis: .vertical)
                        .lineLimit(3...8).focused($focused).accessibilityIdentifier("mappingNotes")
                }
                DraftPhotosSection()
                Section {
                    Button {
                        focused = false
                        if w.draft.photos.isEmpty {
                            // Preserve the existing synchronous field-only save/focus transition.
                            mapping.perform { _ = try $0.save(); mapping.success = true }
                        } else {
                            let id = w.draft.id
                            Task { await mapping.saveDraft(id: id) }
                        }
                    } label: {
                        Text("Сохранить наблюдение").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("saveMappingObservation")
                        .disabled(!w.draft.photoSessions.isEmpty || mapping.photoBusy)
                    if !w.draft.photoSessions.isEmpty { Text("Дождитесь завершения выбора и получения всех фотографий.").font(.caption) }
                    if w.draft.saving { ProgressView("Сохранение наблюдения и фотографий…") }
                }
            }.scrollDismissesKeyboard(.interactively)
                // A new draft also needs a fresh Form/focus/presentation lifetime.
                .id(w.draft.id)
        }.disabled(w.draft.saving).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
    private func coordinate(_ name: String, _ key: WritableKeyPath<MappingDraft, String>) -> some View {
        MappingCoordinateField(title: name,
            text: draft(key, fallback: ""), identifier: "mapping\(name)", focus: $coordinateFocus)
    }
    private func selector(_ title: String, id: String, values: [(UUID, String)], selection: Binding<UUID?>, kind: ContextEditorKind) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Picker(title, selection: selection) {
                    Text("Не выбрано").tag(nil as UUID?)
                    ForEach(values, id: \.0) { value in Text(value.1).tag(Optional(value.0)) }
                }.labelsHidden().frame(minHeight: 44).accessibilityIdentifier(id)
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
                        if let editingID {
                            NavigationLink("DXF: план и версии") { HorizonPlansView(horizonID: editingID) }
                        }
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
                else {
                    let id = try mapping.workflow!.createHorizon(elevation: elevation, datum: datum)
                    load(id)
                }
            case .excavation:
                if let editingID { try mapping.workflow!.updateExcavation(id: editingID, name: name, horizonIDs: horizonIDs) }
                else { try mapping.workflow!.createExcavation(name: name, horizonIDs: horizonIDs) }
            }
            if kind != .horizon { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

private struct ExcavationSelectionView: View {
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: UUID?
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Button("Не выбрано") { selection = nil; dismiss() }
                ForEach((mapping.workflow?.excavations ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { excavation in
                    Button { selection = excavation.id; dismiss() } label: {
                        HStack {
                            Text(excavation.name)
                            Spacer()
                            if selection == excavation.id { Image(systemName: "checkmark") }
                        }.frame(minHeight: 44)
                    }
                }
                NavigationLink("Управление выработками") { ContextEditor(kind: .excavation) }
            }.navigationTitle("Выработки")
                .searchable(text: $search, prompt: "Название выработки")
                .toolbar { Button("Закрыть") { dismiss() } }
        }
    }
}

/// Unfocused text is presentation only. Focusing exposes the exact original input for editing.
struct MappingCoordinateField: View {
    let title: String
    @Binding var text: String
    let identifier: String
    let focus: Binding<String?>
    var body: some View {
        HStack {
            Text(title).frame(width: 42, alignment: .leading)
            LosslessNumericField(text: $text,
                displayText: (try? ElevationInput.meters(text)).map(EngineeringDisplay.coordinate) ?? text,
                focused: focus.wrappedValue == identifier, identifier: identifier) { active in
                    if active { focus.wrappedValue = identifier }
                    else if focus.wrappedValue == identifier { focus.wrappedValue = nil }
                }
        }
        .contentShape(Rectangle()).onTapGesture { focus.wrappedValue = identifier }
    }
}
