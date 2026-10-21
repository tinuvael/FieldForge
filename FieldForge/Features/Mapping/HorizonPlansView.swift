import SwiftUI
import UniformTypeIdentifiers

struct HorizonPlansView: View {
    @EnvironmentObject private var mapping: MappingModel
    var selecting = false
    var onSelection: (() -> Void)?
    var horizonID: UUID? = nil
    private var effectiveHorizonID: UUID? { horizonID ?? mapping.workflow?.context.horizonID }
    private var plans: [MappingPlanReference] { effectiveHorizonID.map { mapping.plans(for: $0) } ?? [] }
    @State private var importing = false
    @State private var prepared: PreparedPlanImport?
    @State private var error: String?
    @State private var pending: [MappingPlanReference] = []
    @State private var busy = false
    var body: some View {
        List {
            Section {
                Text(mapping.workflow?.journal.horizons.first { $0.id == effectiveHorizonID }?.displayName ?? "Выберите горизонт в картировании")
                    .font(.headline)
                Button("Загрузить DXF", systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(effectiveHorizonID == nil || busy || mapping.planStore == nil)
                    .accessibilityIdentifier("importDXF")
                if busy { ProgressView("Проверка DXF…") }
                if let effectiveHorizonID, mapping.hasUnavailablePlanSelection(for: effectiveHorizonID) {
                    Label("Прежний выбор недоступен. Выберите ревизию для просмотра.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                ForEach(["P2_PLAN_A", "P2_PLAN_B"], id: \.self) { key in
                    if let text = ProcessInfo.processInfo.environment[key] {
                        Button("Тестовый DXF: \(key)") {
                            guard let h = effectiveHorizonID else { return }
                            prepare(data: Data(text.utf8), filename: "\(key).dxf", horizonID: h)
                        }.accessibilityIdentifier(key)
                    }
                }
            }
            #endif
            Section("Планы и версии") {
                ForEach(plans) { plan in
                    NavigationLink {
                        HorizonPlanLoader(plan: plan, selecting: selecting, onSelection: onSelection)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(plan.file?.originalFilename ?? "Старая ссылка без файла")
                            Text("Версия: \(plan.version)").font(.subheadline)
                            if mapping.activePlan(for: plan.horizonID)?.id == plan.id {
                                Text(mapping.hasExplicitPlan(for: plan.horizonID) ? "Активная для просмотра" : "Последний импорт · для просмотра").font(.caption).foregroundStyle(.secondary)
                            }
                            if selecting, mapping.workflow?.draft.planID == plan.id {
                                Text("Источник координат черновика").font(.caption)
                            }
                            Text(plan.file?.units.label ?? "Единицы неизвестны").font(.caption)
                        }
                    }.accessibilityIdentifier("plan-\(plan.id.uuidString)")
                    if !selecting {
                        Button("Показывать версию \(plan.version)") { mapping.selectActivePlan(plan) }
                            .disabled(mapping.activePlan(for: plan.horizonID)?.id == plan.id && mapping.hasExplicitPlan(for: plan.horizonID))
                    }
                }
                if plans.isEmpty { Text("На этом горизонте пока нет DXF") }
            }
            if !pending.isEmpty {
                Section("Незавершённые импорты · оригиналы сохранены") {
                    ForEach(pending) { plan in
                        Button("Восстановить: \(plan.file?.originalFilename ?? plan.id.uuidString) · \(plan.version)") {
                            recover(plan)
                        }
                    }
                }
            }
            DisclosureGroup("Помощь по DXF") {
                Text("Текстовый DXF: LINE, LWPOLYLINE, 2D/3D POLYLINE (XY-проекция), ARC, CIRCLE, POINT, простые TEXT/MTEXT. BLOCK/INSERT и кривые bulge пропускаются с предупреждением. Не DWG.").font(.caption)
                Text("Локальные координаты чертежа не подтверждают съёмочную точность. Z берётся из горизонта либо вводится вручную. GPS не используется.").font(.caption)
            }
        }.navigationTitle("Планы горизонта")
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "dxf") ?? .data]) { result in
                switch result {
                case .success(let url): prepare(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(item: $prepared, onDismiss: refreshPending) { item in
                PlanImportSetup(item: item, previousPlan: plans.last, existingVersions: (plans + pending).filter { $0.horizonID == item.horizonID }.map(\.version), stage: { units, version, crs, axes, confirmation in
                    guard let files = mapping.planStore else { throw StorageError.writesBlocked }
                    try PlanRevisionNumber.validateNew(version, existing: ((mapping.workflow?.journal.plans ?? []) + pending).filter { $0.horizonID == item.horizonID }.map(\.version))
                    let preview = MappingPlanReference(id: UUID(), horizonID: item.horizonID, attachmentID: UUID(), version: version,
                        file: ManagedPlanFile(originalFilename: item.filename, sha256: ManagedPlanStore.digest(item.data), byteCount: item.data.count,
                            importedAt: Date(), units: units, crs: crs.isEmpty ? "unknown" : crs, axes: axes.isEmpty ? "unknown" : axes,
                            unitDeclaration: "userConfirmedAtImport", insertionUnits: item.drawing.insertionUnits), frameConfirmation: confirmation)
                    try PlanCoordinateCompatibility.validate((mapping.workflow?.journal.plans ?? []) + [preview])
                    return try await Task.detached(priority: .userInitiated) {
                        try files.stage(data: item.data, filename: item.filename, horizonID: item.horizonID,
                                        version: version, units: units, crs: crs, axes: axes, frameConfirmation: confirmation)
                    }.value
                }, register: { plan in
                    // Import context was frozen at file selection, independent of subsequent navigation.
                    guard mapping.workflow != nil else { throw StorageError.writesBlocked }
                    try mapping.workflow!.registerPlan(plan)
                    mapping.planStore?.complete(plan); refreshPending()
                })
            }
            .alert("План", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .onAppear { refreshPending() }
            .onChange(of: effectiveHorizonID) { _, _ in refreshPending() }
    }
    private func refreshPending() {
        do {
            let items = try mapping.planStore?.pending() ?? []
            for plan in items where mapping.workflow?.journal.plans.contains(plan) == true { mapping.planStore?.complete(plan) }
            pending = items.filter { plan in
                plan.horizonID == effectiveHorizonID && mapping.workflow?.journal.plans.contains(plan) != true
            }
        } catch { self.error = "Не удалось прочитать журнал импорта: \(error.localizedDescription). Файлы сохранены." }
    }
    private func prepare(data: Data, filename: String, horizonID: UUID) {
        busy = true
        Task {
            defer { busy = false }
            do {
                prepared = try await Task.detached(priority: .userInitiated) {
                    try PreparedPlanImport(id: UUID(), horizonID: horizonID, filename: filename,
                        data: data, drawing: DXFDocument.parse(data))
                }.value
            } catch { self.error = error.localizedDescription }
        }
    }
    private func recover(_ plan: MappingPlanReference) {
        busy = true
        Task {
            defer { busy = false }
            do {
                guard let files = mapping.planStore, mapping.workflow != nil else { throw StorageError.writesBlocked }
                _ = try await Task.detached(priority: .userInitiated) { try DXFDocument.parse(files.read(plan)) }.value
                try mapping.workflow!.registerPlan(plan); files.complete(plan); refreshPending()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func prepare(_ url: URL) {
        guard let horizonID = effectiveHorizonID else { return }
        busy = true
        Task {
            do {
                let item = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    var failure: NSError?, result: Result<Data, Error>?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failure) { coordinated in
                        result = Result {
                            let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                            guard size <= 10_000_000 else { throw MappingError.invalid("DXF превышает 10 МБ.") }
                            return try Data(contentsOf: coordinated)
                        }
                    }
                    if let failure { throw failure }
                    guard let result else { throw StorageError.invalidRecord }
                    let data = try result.get()
                    return try PreparedPlanImport(id: UUID(), horizonID: horizonID, filename: url.lastPathComponent,
                                                  data: data, drawing: DXFDocument.parse(data))
                }.value
                prepared = item
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct PreparedPlanImport: Identifiable {
    let id: UUID, horizonID: UUID
    let filename: String
    let data: Data
    let drawing: DXFDocument
}

private struct PlanImportSetup: View {
    let item: PreparedPlanImport
    let previousPlan: MappingPlanReference?
    let existingVersions: [String]
    let stage: (PlanUnits, String, String, String, PlanFrameConfirmation?) async throws -> MappingPlanReference
    let register: (MappingPlanReference) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool
    @State private var staged: MappingPlanReference?
    @State private var busy = false
    @State private var sameFrame = false
    @State private var units = PlanUnits.unknown
    @State private var version = "1"
    @State private var initializedVersion = false
    @State private var crs = ""
    @State private var axes = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Импорт DXF") {
                    Text(item.filename)
                    LabeledContent("Ревизия", value: version)
                    DisclosureGroup("Изменить номер ревизии") {
                        TextField("Номер ревизии", text: $version).keyboardType(.numberPad).focused($inputFocused)
                            .accessibilityIdentifier("planVersion").disabled(staged != nil || busy)
                    }
                    Picker("Единицы XY · подтвердите источник", selection: $units) {
                        ForEach(PlanUnits.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("planUnits").disabled(staged != nil || busy)
                    Text("XY сохраняются без пересчёта. Подтвердите единицы по источнику. Неизвестная СК не означает съёмочные координаты. Z — в метрах.")
                        .font(.caption)
                }
                if let previousPlan, let file = previousPlan.file {
                    Section {
                        Toggle("Система координат совпадает с предыдущей ревизией", isOn: $sameFrame)
                            .disabled(staged != nil || busy || file.units == .unknown)
                            .accessibilityIdentifier("planSameCoordinateFrame")
                            .onChange(of: sameFrame) { _, on in
                                if on { units = file.units; crs = file.crs; axes = file.axes }
                            }
                        Text("Предыдущая ревизия: \(previousPlan.version)").font(.caption)
                        if file.units == .unknown {
                            Text("У предыдущей ревизии неизвестны единицы. Для совместного показа импортируйте план с подтверждёнными единицами и СК.").font(.caption)
                        }
                    }
                }
                DisclosureGroup("СК и направления осей") {
                    TextField("СК / неизвестно", text: $crs).focused($inputFocused).disabled(staged != nil || busy)
                    TextField("Оси / неизвестно", text: $axes).focused($inputFocused).disabled(staged != nil || busy)
                }
                DisclosureGroup("Ограничения просмотра · \(item.drawing.warnings.count)") {
                    ForEach(item.drawing.warnings, id: \.self) { Text($0).font(.caption) }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if busy { ProgressView("Сохранение оригинала…") }
                Button(staged == nil ? "Сохранить план офлайн" : "Повторить регистрацию") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            if staged == nil {
                                let confirmation = sameFrame ? previousPlan.map { PlanFrameConfirmation(previousPlanID: $0.id, confirmedAt: Date()) } : nil
                                staged = try await stage(units, version, crs, axes, confirmation)
                            }
                            guard let staged else { throw StorageError.invalidRecord }
                            try register(staged); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy).accessibilityIdentifier("savePlanImport")
            }.navigationTitle("Импорт DXF").interactiveDismissDisabled(busy)
                .onAppear {
                    guard !initializedVersion else { return }
                    initializedVersion = true
                    do { version = try PlanRevisionNumber.next(existingVersions) }
                    catch { self.error = error.localizedDescription }
                }
               .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(busy) }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { inputFocused = false } }
                }
        }
    }
}

struct HorizonPlanLoader: View {
    let plan: MappingPlanReference
    let selecting: Bool
    let onSelection: (() -> Void)?
    var onPointSelection: ((PlanPoint, MappingPlanReference) throws -> Void)? = nil
    @EnvironmentObject private var mapping: MappingModel
    @State private var drawing: DXFDocument?
    @State private var error: String?
    var body: some View {
        Group {
            if let drawing { HorizonPlanView(plan: plan, drawing: drawing, selecting: selecting, onSelection: onSelection, onPointSelection: onPointSelection) }
            else if let error { ContentUnavailableView("План недоступен", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView("Проверка оригинала…") }
        }.task(id: plan.id) {
            drawing = nil; error = nil
            do {
                guard let files = mapping.planStore else { throw StorageError.writesBlocked }
                let parsed = try await Task.detached(priority: .userInitiated) { try DXFDocument.parse(files.read(plan)) }.value
                guard !Task.isCancelled else { return }
                drawing = parsed
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct HorizonPlanView: View {
    let plan: MappingPlanReference
    let drawing: DXFDocument
    let selecting: Bool
    let onSelection: (() -> Void)?
    var onPointSelection: ((PlanPoint, MappingPlanReference) throws -> Void)? = nil
    @EnvironmentObject private var mapping: MappingModel
    @State private var zoom = 1.0
    @GestureState private var magnification = 1.0
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @State private var proposed: PlanPoint?
    @State private var filter: UUID?
    @State private var pointSelection: PlanPointSelection?
    @State private var properties = false
    @State private var error: String?
    private var points: [MappingObservation] { mapping.workflow?.points(on: plan, excavationID: filter, restrictToSelection: selecting && onPointSelection == nil) ?? [] }
    private func canvasDescription(_ viewport: PlanViewport) -> String {
        let visibleMarkers = points.filter { record in
            guard let x = record.coordinates?.x, let y = record.coordinates?.y else { return false }
            return viewport.containsScreenPoint(viewport.screen(PlanPoint(x: x, y: y)))
        }.count
        let vertexCount = drawing.polylines.reduce(0) { $0 + $1.vertices.count }
        return "Полилинии: \(drawing.polylines.count); вершины: \(vertexCount); маркеры в окне: \(visibleMarkers); POINT: \(drawing.points.count); подписи: \(drawing.labels.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let viewport = PlanViewport(bounds: drawing.bounds, width: geometry.size.width, height: geometry.size.height,
                    zoom: min(100, max(0.1, zoom * magnification)),
                    pan: PlanPoint(x: pan.width + drag.width, y: pan.height + drag.height))
                Canvas { context, size in
                    for vertices in drawing.paths {
                        var path = Path()
                        for (index, vertex) in vertices.enumerated() {
                            let p = viewport.screen(vertex), cg = CGPoint(x: p.x, y: p.y)
                            if index == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
                        }
                        context.stroke(path, with: .color(.primary.opacity(0.7)), lineWidth: 1)
                    }
                    for dot in drawing.points {
                        let p = viewport.screen(dot.xy)
                        guard viewport.containsScreenPoint(p) else { continue }
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(.primary))
                    }
                    for label in drawing.labels {
                        let p = viewport.screen(label.position.xy)
                        var textContext = context
                        textContext.translateBy(x: p.x, y: p.y)
                        textContext.rotate(by: .degrees(-label.rotationDegrees))
                        textContext.draw(Text(label.text).font(.system(size: min(96, max(6, label.height * viewport.scale))))
                            .foregroundColor(.primary), at: .zero, anchor: label.topAligned ? .topLeading : .bottomLeading)
                    }
                    for record in points {
                        if let x = record.coordinates?.x, let y = record.coordinates?.y {
                            let p = viewport.screen(PlanPoint(x: x, y: y))
                            guard viewport.containsScreenPoint(p) else { continue }
                            context.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(.blue))
                            context.draw(Text(record.displayPicket).font(.caption).foregroundColor(.blue), at: CGPoint(x: p.x + 10, y: p.y - 12), anchor: .leading)
                        }
                    }
                    if let proposed {
                        let p = viewport.screen(proposed)
                        let rect = CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)
                        context.stroke(Path(ellipseIn: rect), with: .color(.orange), lineWidth: 3)
                        context.draw(Text("Новая").font(.caption).foregroundColor(.orange), at: CGPoint(x: p.x, y: p.y + 24))
                    }
                }.background(Color(uiColor: .secondarySystemBackground))
                    .contentShape(Rectangle()).accessibilityIdentifier("planCanvas")
                    .accessibilityLabel("План. Синие точки — журнал, оранжевая — новая точка")
                    .accessibilityValue(canvasDescription(viewport))
                    .gesture(DragGesture(minimumDistance: 5).updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { pan.width += $0.translation.width; pan.height += $0.translation.height })
                    .simultaneousGesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }
                        .onEnded { zoom = min(100, max(0.1, zoom * $0)) })
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in
                        let location = PlanPoint(x: value.location.x, y: value.location.y)
                        let hits = points.filter { record in
                            guard let x = record.coordinates?.x, let y = record.coordinates?.y else { return false }
                            let p = viewport.screen(PlanPoint(x: x, y: y))
                            return hypot(p.x - location.x, p.y - location.y) <= 24
                        }
                        if !hits.isEmpty { pointSelection = PlanPointSelection(records: hits) }
                        else if selecting { proposed = viewport.drawing(location) }
                    })
            }
            HStack {
                Button("−") { zoom = max(0.1, zoom / 1.5) }.accessibilityIdentifier("planZoomOut")
                Button("Вписать") { zoom = 1; pan = .zero }.accessibilityIdentifier("planFit")
                Button("+") { zoom = min(100, zoom * 1.5) }.accessibilityIdentifier("planZoomIn")
                Spacer()
                Button("Точки: \(points.count)") { pointSelection = PlanPointSelection(records: points) }.accessibilityIdentifier("planPoints")
            }.buttonStyle(.bordered).controlSize(.regular).padding(.horizontal).padding(.top, 8).padding(.bottom, 16)
            if let proposed {
                VStack {
                    Text("Новая: X \(EngineeringDisplay.coordinate(proposed.x)), Y \(EngineeringDisplay.coordinate(proposed.y))")
                        .font(.caption).accessibilityIdentifier("planProposedXY")
                    Button("Подтвердить X/Y") {
                        do {
                            guard mapping.workflow != nil else { throw StorageError.writesBlocked }
                            if let onPointSelection { try onPointSelection(proposed, plan) }
                            else { try mapping.workflow!.selectPlanPoint(proposed, planID: plan.id) }
                            onSelection?()
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("confirmPlanXY")
                    Button("Отменить точку") { self.proposed = nil }
                }.padding(8)
            }
        }.navigationTitle(plan.file?.originalFilename ?? "DXF").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Menu {
                    Button("Свойства и ограничения", systemImage: "info.circle") { properties = true }
                    Picker("Выработка", selection: $filter) {
                        Text("Все выработки").tag(nil as UUID?)
                        ForEach(mapping.workflow?.journal.excavations.filter { $0.horizonIDs.contains(plan.horizonID) } ?? []) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                } label: { Label("Параметры плана", systemImage: "ellipsis.circle") }
            }
            .sheet(item: $pointSelection) { selection in
                let records = selection.records.compactMap { old in points.first { $0.id == old.id } }
                NavigationStack {
                    List(records) { record in
                        NavigationLink {
                            MappingObservationDetail(record: record)
                               .toolbar { ToolbarItem(placement: .cancellationAction) {
                                    Button("Закрыть") { pointSelection = nil }
                                } }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(mapping.workflow?.journal.excavations.first { $0.id == record.excavationID }?.name ?? "Выработка").font(.headline)
                                Text(record.displayPicket).font(.subheadline)
                                Text(MappingDateText.compact(record)).font(.caption)
                            }
                        }.accessibilityIdentifier("planPoint-\(record.id.uuidString)")
                    }.navigationTitle("Наблюдения: \(records.count)")
                       .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { pointSelection = nil }
                        } }
                }
            }
            .sheet(isPresented: $properties) {
                NavigationStack {
                    List {
                        Text("Версия: \(plan.version)")
                        Text("СК: \(plan.file?.crs ?? "unknown")")
                        Text("Оси: \(plan.file?.axes ?? "unknown")")
                        Text("XY: \(plan.file?.units.label ?? "unknown"); без преобразования координат")
                        Text("Z: отдельная отметка в метрах; не получена из DXF")
                        Text("Показаны точки исходной и совместимых ревизий в этом проекте и горизонте. Координаты и исходные ссылки не изменяются.")
                        if let confirmation = plan.frameConfirmation {
                            Text("Совпадение СК подтверждено при импорте: \(confirmation.confirmedAt.formatted())")
                        }
                        Text("Если прежних точек нет: при импорте новой ревизии подтвердите совпадение СК с предыдущей либо укажите одинаковые подтверждённые СК, оси и единицы. При противоречии исправьте метаданные источника и импортируйте новую ревизию.")
                        ForEach(drawing.warnings, id: \.self) { Text($0) }
                        Text("SHA-256: \(plan.file?.sha256 ?? "unknown")").textSelection(.enabled).font(.caption)
                    }.navigationTitle("Свойства и ограничения").toolbar { Button("Закрыть") { properties = false } }
                }
            }
            .alert("План", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
}

private struct PlanPointSelection: Identifiable {
    let id = UUID()
    let records: [MappingObservation]
}
