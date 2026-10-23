import SwiftUI
import UniformTypeIdentifiers

struct HorizonPlansView: View {
    @EnvironmentObject private var mapping: MappingModel
    var selecting = false
    var onSelection: (() -> Void)?
    var horizonID: UUID? = nil
    private var effectiveHorizonID: UUID? { horizonID ?? mapping.workflow?.context.horizonID }
    private var plans: [MappingPlanReference] { effectiveHorizonID.map { mapping.plans(for: $0, archived: showingArchive) } ?? [] }
    @State private var showingArchive = false
    @State private var management: PlanRevisionActionRequest?
    @State private var importing = false
    @State private var prepared: PreparedPlanImport?
    @State private var sourceRecovery: MappingPlanReference?
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
                Picker("Ревизии", selection: $showingArchive) {
                    Text("Планы").tag(false)
                    Text("Архив").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("planArchiveFilter")
                ForEach(plans) { plan in
                    VStack(alignment: .leading, spacing: 6) {
                        NavigationLink {
                            HorizonPlanLoader(plan: plan, selecting: selecting && plan.isAvailable, onSelection: onSelection)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.file?.originalFilename ?? "Старая ссылка без файла").font(.headline)
                                Text("\(horizonName(plan.horizonID)) · Ревизия \(plan.version)").font(.subheadline)
                                if plan.isArchived {
                                    Label("Архивная", systemImage: "archivebox").font(.caption)
                                } else if mapping.activePlan(for: plan.horizonID)?.id == plan.id {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Активная").accessibilityIdentifier("activePlan-\(plan.version)")
                                    }.font(.caption).foregroundStyle(.blue)
                                } else { Text("Неактивная").font(.caption).foregroundStyle(.secondary) }
                                if let file = plan.file {
                                    Text(file.importedAt.formatted(date: .numeric, time: .shortened)).font(.caption)
                                }
                            }
                        }.accessibilityIdentifier("plan-\(plan.id.uuidString)")
                        HStack {
                            if !plan.isArchived {
                                Button("Сделать активной") { mapping.selectActivePlan(plan) }
                                    .disabled(mapping.activePlan(for: plan.horizonID)?.id == plan.id && mapping.hasExplicitPlan(for: plan.horizonID))
                                    .accessibilityIdentifier("activatePlan-\(plan.version)")
                            }
                            Spacer()
                            Menu("Действия", systemImage: "ellipsis.circle") {
                                NavigationLink("Открыть") { HorizonPlanLoader(plan: plan, selecting: false, onSelection: nil) }
                                Button(plan.isArchived ? "Вернуть из архива" : "Архивировать") {
                                    management = PlanRevisionActionRequest(plan: plan, action: plan.isArchived ? .restore : .archive)
                                }
                                Button("Перенести на другой горизонт") { management = PlanRevisionActionRequest(plan: plan, action: .move) }
                                Button("Удалить", role: .destructive) { management = PlanRevisionActionRequest(plan: plan, action: .delete) }
                            }.accessibilityIdentifier("planActions-\(plan.version)")
                        }.font(.subheadline).buttonStyle(.borderless)
                    }
                }
                if plans.isEmpty { Text(showingArchive ? "Архив этого горизонта пуст" : "На этом горизонте пока нет DXF") }
            }
            if !pending.isEmpty {
                Section("Незавершённые импорты · файлы не удалены") {
                    ForEach(pending) { plan in
                        Button("Восстановить: \(plan.file?.originalFilename ?? plan.id.uuidString) · \(plan.version)") {
                            recover(plan)
                        }
                        Button("Выбрать тот же исходный DXF для восстановления") {
                            sourceRecovery = plan; importing = true
                        }.font(.caption)
                    }
                }
            }
            DisclosureGroup("Помощь по DXF") {
                Text("Текстовый DXF: LINE, LWPOLYLINE, 2D/3D POLYLINE (XY-проекция), ARC, CIRCLE, POINT, простые TEXT/MTEXT. Прямые внутри BLOCK/INSERT поддерживаются при стандартном направлении оси Z. Кривые bulge пропускаются с предупреждением. Не DWG.").font(.caption)
                Text("Локальные координаты чертежа не подтверждают съёмочную точность. Z предлагается по явной высотной геометрии DXF рядом с точкой при подтверждённых единицах; иначе — ручной ввод. Номер горизонта не задаёт Z точки. GPS не используется.").font(.caption)
            }
        }.accessibilityIdentifier("planRevisionList").navigationTitle("Планы горизонта")
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "dxf") ?? .data]) { result in
                switch result {
                case .success(let url):
                    let recovery = sourceRecovery; sourceRecovery = nil
                    prepare(url, recovering: recovery)
                case .failure(let failure): sourceRecovery = nil; error = failure.localizedDescription
                }
            }
            .sheet(item: $prepared, onDismiss: refreshPending) { item in
                PlanImportSetup(item: item, horizonName: horizonName(item.horizonID), previousPlan: mapping.activePlan(for: item.horizonID), existingVersions: ((mapping.workflow?.journal.plans ?? []) + pending).filter { $0.horizonID == item.horizonID && !$0.isDeleted }.map(\.version), stage: { units, version, crs, axes, confirmation in
                    guard let files = mapping.planStore else { throw StorageError.writesBlocked }
                    let knownPlans = ((mapping.workflow?.journal.plans ?? []) + pending).filter { $0.id != item.id }
                    let data = item.data, filename = item.filename, horizon = item.horizonID
                    let id = item.id, importedAt = item.importedAt, insertionUnits = item.drawing.insertionUnits
                    return try await mapping.storage.run {
                        try PlanRevisionNumber.validateNew(version, existing: knownPlans.filter { $0.horizonID == horizon && !$0.isDeleted }.map(\.version))
                        let preview = MappingPlanReference(id: id, horizonID: horizon, attachmentID: id, version: version,
                            file: ManagedPlanFile(originalFilename: filename, sha256: ManagedPlanStore.digest(data), byteCount: data.count,
                                importedAt: importedAt, units: units, crs: crs.isEmpty ? "unknown" : crs, axes: axes.isEmpty ? "unknown" : axes,
                                unitDeclaration: PlanUnits.declared(by: insertionUnits) == units ? "dxfINSUNITS" : "userConfirmedAtImport", insertionUnits: insertionUnits), frameConfirmation: confirmation)
                        try PlanCoordinateCompatibility.validate(knownPlans + [preview])
                        return try files.stage(data: data, filename: filename, horizonID: horizon,
                            version: version, units: units, crs: crs, axes: axes, frameConfirmation: confirmation,
                            id: id, attachmentID: id, importedAt: importedAt)
                    }
                }, register: { plan in
                    // Import context was frozen at file selection, independent of subsequent navigation.
                    try await mapping.registerPlan(plan)
                    mapping.selectActivePlanIfUnset(plan); refreshPending()
                })
            }
            .sheet(item: $management) { PlanRevisionActionsView(request: $0) }
            .alert("План", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .onAppear { refreshPending() }
            .onChange(of: effectiveHorizonID) { _, _ in refreshPending() }
    }
    private func horizonName(_ id: UUID) -> String { mapping.workflow?.journal.horizons.first { $0.id == id }?.displayName ?? "Неизвестно" }
    private func refreshPending() {
        Task {
            do {
                let items = try await mapping.pendingPlans()
                pending = items.filter { plan in
                    plan.horizonID == effectiveHorizonID && mapping.workflow?.journal.plans.contains(where: { $0.matchesImport(plan) }) != true
                }
            } catch { self.error = "Не удалось прочитать журнал импорта: \(error.localizedDescription). Файлы сохранены." }
        }
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
                try await mapping.registerPlan(plan); refreshPending()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func prepare(_ url: URL, recovering: MappingPlanReference? = nil) {
        guard let horizonID = recovering?.horizonID ?? effectiveHorizonID else { return }
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
                if let recovering {
                    guard let files = mapping.planStore else { throw StorageError.writesBlocked }
                    let bytes = item.data
                    try await mapping.storage.run { try files.supply(bytes, for: recovering) }
                    try await mapping.registerPlan(recovering)
                    refreshPending()
                } else { prepared = item }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct PreparedPlanImport: Identifiable, Sendable {
    let id: UUID, horizonID: UUID
    let filename: String
    let data: Data
    let drawing: DXFDocument
    let importedAt = Date()
}

private struct PlanImportSetup: View {
    let item: PreparedPlanImport
    let horizonName: String
    let previousPlan: MappingPlanReference?
    let existingVersions: [String]
    let stage: (PlanUnits, String, String, String, PlanFrameConfirmation?) async throws -> MappingPlanReference
    let register: (MappingPlanReference) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool
    @State private var staged: MappingPlanReference?
    @State private var busy = false
    @State private var sameFrame = false
    @State private var confirmedHorizon = false
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
                    LabeledContent("Целевой горизонт", value: horizonName).accessibilityIdentifier("planImportHorizon")
                    Toggle("Подтверждаю горизонт \(horizonName)", isOn: $confirmedHorizon)
                        .disabled(staged != nil || busy).accessibilityIdentifier("confirmPlanHorizon")
                    HStack {
                        Text("Ревизия")
                        TextField("Номер ревизии", text: $version).keyboardType(.numberPad).focused($inputFocused)
                            .accessibilityIdentifier("planVersion").disabled(staged != nil || busy)
                    }
                    LabeledContent("Единицы в DXF · $INSUNITS", value: item.drawing.insertionUnits.map(String.init) ?? "Не заданы")
                    if let declared = PlanUnits.declared(by: item.drawing.insertionUnits) {
                        LabeledContent("Единицы XY", value: declared.label)
                    } else {
                        Picker("Единицы DXF · подтвердите источник", selection: $units) {
                            Text("Уточните единицы").tag(PlanUnits.unknown)
                            Text("Метры").tag(PlanUnits.meters)
                            Text("Миллиметры").tag(PlanUnits.millimeters)
                        }.accessibilityIdentifier("planUnits").disabled(staged != nil || busy)
                    }
                    Text("XY сохраняются без пересчёта. Неизвестная СК не означает съёмочные координаты. Z — в метрах.")
                        .font(.caption)
                }
                if let previousPlan, let file = previousPlan.file {
                    Section {
                        Toggle("Система координат совпадает с предыдущей ревизией", isOn: $sameFrame)
                            .disabled(staged != nil || busy || file.units == .unknown)
                            .accessibilityIdentifier("planSameCoordinateFrame")
                            .onChange(of: sameFrame) { _, on in
                                if on { crs = file.crs; axes = file.axes }
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
                            try await register(staged); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy || !confirmedHorizon || units == .unknown).accessibilityIdentifier("savePlanImport")
            }.navigationTitle("Импорт DXF").interactiveDismissDisabled(busy)
                .onAppear {
                    guard !initializedVersion else { return }
                    initializedVersion = true
                    units = PlanUnits.declared(by: item.drawing.insertionUnits) ?? .unknown
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
    var onPointSelection: ((PlanPoint, MappingPlanReference, PlanGeometryElevation?) throws -> Void)? = nil
    @EnvironmentObject private var mapping: MappingModel
    private var currentPlan: MappingPlanReference { mapping.workflow?.journal.plans.first { $0.id == plan.id } ?? plan }
    @State private var drawing: DXFDocument?
    @State private var error: String?
    var body: some View {
        Group {
            if let drawing { HorizonPlanView(plan: currentPlan, drawing: drawing, selecting: selecting, onSelection: onSelection, onPointSelection: onPointSelection) }
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
    var onPointSelection: ((PlanPoint, MappingPlanReference, PlanGeometryElevation?) throws -> Void)? = nil
    @State private var elevationResolution = PlanElevationResolution(candidates: [], requiresChoice: false)
    @EnvironmentObject private var mapping: MappingModel
    @State private var zoom = 1.0
    @GestureState private var magnification = 1.0
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @State private var proposed: PlanPoint?
    @State private var filter: UUID?
    @State private var pointSelection: PlanPointSelection?
    @State private var properties = false
    @State private var reviewedUnits = PlanUnits.unknown
    @State private var error: String?
    private var points: [MappingObservation] { mapping.workflow?.points(on: plan, excavationID: filter, restrictToSelection: selecting && onPointSelection == nil) ?? [] }
    private func canvasDescription(_ viewport: PlanViewport, points: [MappingObservation]) -> String {
        let visibleMarkers = points.filter { record in
            guard let x = record.coordinates?.x, let y = record.coordinates?.y else { return false }
            return viewport.containsScreenPoint(viewport.screen(PlanPoint(x: x, y: y)))
        }.count
        let vertexCount = drawing.polylines.reduce(0) { $0 + $1.vertices.count }
        return "Полилинии: \(drawing.polylines.count); вершины: \(vertexCount); маркеры в окне: \(visibleMarkers); POINT: \(drawing.points.count); подписи: \(drawing.labels.count)"
    }

    private func elevationLabel(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + EngineeringDisplay.number(value, decimals: 2) + " м"
    }
    private func propose(_ point: PlanPoint) {
        proposed = point
        elevationResolution = PlanElevationSnap.resolve(point, document: drawing, plan: plan)
    }

    private var needsUnitConfirmation: Bool {
        plan.file?.units == .unknown && plan.elevationUnitConfirmation == nil
    }
    private var unitConfirmation: some View {
        VStack(spacing: 4) {
            Picker("Единицы DXF", selection: $reviewedUnits) {
                Text("Уточните единицы").tag(PlanUnits.unknown)
                Text("Метры").tag(PlanUnits.meters)
                Text("Миллиметры").tag(PlanUnits.millimeters)
            }.accessibilityIdentifier("reviewPlanZUnits")
            Button("Подтвердить единицы для Z") {
                let units = reviewedUnits
                Task { do {
                    try await mapping.persist { try $0.confirmPlanElevationUnits(plan.id, units: units) }
                    // Loader supplies the updated plan; onChange recalculates the existing tap.
                } catch { self.error = error.localizedDescription } }
            }.disabled(mapping.isSaving || reviewedUnits == .unknown).accessibilityIdentifier("confirmPlanZUnits")
        }
    }

    var body: some View {
        let points = self.points
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
                    .accessibilityValue(canvasDescription(viewport, points: points))
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
                        else if selecting { propose(viewport.drawing(location)) }
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
                    if let elevation = elevationResolution.automatic {
                        Text("Z ≈ \(elevationLabel(elevation.elevationMeters))")
                            .font(.caption).accessibilityIdentifier("planProposedZ")
                    } else {
                        Text("Z недоступна").font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("planZWarning")
                    }
                    Button("Использовать точку") {
                        do {
                            if let onPointSelection { try onPointSelection(proposed, plan, elevationResolution.automatic) }
                            else { try mapping.performThrowing { try $0.selectPlanPoint(proposed, planID: plan.id, elevation: elevationResolution.automatic) } }
                            onSelection?()
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("confirmPlanXY")
                }.padding(8)
            }
        }.onChange(of: plan) { _, _ in if let proposed { propose(proposed) } }
            .navigationTitle(plan.file?.originalFilename ?? "DXF").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Menu {
                    Button("Сведения о плане", systemImage: "info.circle") { properties = true }
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
                        Section("Сведения о плане") {
                            LabeledContent("Имя файла", value: plan.file?.originalFilename ?? "Неизвестно")
                            LabeledContent("Ревизия", value: plan.version)
                            LabeledContent("Горизонт", value: mapping.workflow?.journal.horizons.first { $0.id == plan.horizonID }?.displayName ?? "Неизвестно")
                            if let file = plan.file {
                                LabeledContent("Дата импорта", value: file.importedAt.formatted(date: .numeric, time: .shortened))
                                LabeledContent("Единицы XY", value: file.units.label)
                                if needsUnitConfirmation { unitConfirmation }
                            }
                        }
                        Section("Совместимость") {
                            Text("Показаны точки этой и совместимых ревизий горизонта.")
                            if let workflow = mapping.workflow {
                                ForEach(workflow.journal.plans.filter { $0.horizonID == plan.horizonID && $0.id != plan.id && !$0.isDeleted }) { other in
                                    let compatible = PlanCoordinateCompatibility.compatible(plan, other, plans: workflow.journal.plans)
                                    LabeledContent("Ревизия \(other.version)", value: compatible ? "Совместима" : "Совместимость не подтверждена")
                                    if !compatible {
                                        Text("Для совместного показа подтвердите единицы и совпадение СК при импорте новой ревизии.").font(.caption)
                                    }
                                }
                            }
                        }
                        Section {
                            DisclosureGroup("Технические сведения") {
                                LabeledContent("СК", value: plan.file?.crs ?? "Неизвестно")
                                LabeledContent("Оси", value: plan.file?.axes ?? "Неизвестно")
                                Text("Z предлагается из явной высотной геометрии DXF; XY остаются в выбранной точке чертежа. Вертикальная система отсчёта DXF неизвестна.")
                                LabeledContent("Сегменты с достоверной Z", value: String(drawing.elevationSegments.count))
                                LabeledContent("Источники Z", value: drawing.elevationEntityTypes.isEmpty ? "Нет" : drawing.elevationEntityTypes.joined(separator: ", "))
                                LabeledContent("Не использовано для Z", value: String(drawing.elevationExclusions.values.reduce(0, +)))
                                LabeledContent("Единицы высоты", value: plan.elevationUnitConfirmation?.units.label ?? plan.file?.units.label ?? "Неизвестно")
                                if let confirmation = plan.elevationUnitConfirmation {
                                    Text("Единицы Z подтверждены: \(confirmation.confirmedAt.formatted())")
                                }
                                LabeledContent("Единицы для Z", value: PlanElevationSnap.metersPerUnit(plan) == nil ? "Не подтверждены / противоречат $INSUNITS" : "Подтверждены")
                                if let proposed {
                                    Text("Выбранная точка: X \(EngineeringDisplay.coordinate(proposed.x)), Y \(EngineeringDisplay.coordinate(proposed.y))")
                                    if let reason = elevationResolution.failureReason { Text(reason).accessibilityIdentifier("planZFailure") }
                                    if let distance = elevationResolution.nearestDistanceMeters {
                                        LabeledContent("До ближайшей высотной линии, м", value: EngineeringDisplay.number(distance))
                                    }
                                } else if drawing.elevationSegments.isEmpty { Text("Нет допустимых сегментов с явной высотой. См. причины исключения объектов.") }
                                ForEach(drawing.elevationExclusions.keys.sorted(), id: \.self) { reason in
                                    Text("\(reason): \(drawing.elevationExclusions[reason] ?? 0)")
                                }
                                Text("План: \(plan.id.uuidString)")
                                Text("Исходный файл: \(plan.attachmentID.uuidString)")
                                if let file = plan.file {
                                    Text("Размер: \(file.byteCount) байт")
                                    Text("Источник единиц: \(file.unitDeclaration)")
                                    Text("DXF $INSUNITS: \(file.insertionUnits.map(String.init) ?? "не задано")")
                                }
                                if let confirmation = plan.frameConfirmation {
                                    Text("Совпадение СК подтверждено при импорте: \(confirmation.confirmedAt.formatted())")
                                    Text("Предыдущая ревизия: \(confirmation.previousPlanID.uuidString)")
                                }
                                ForEach(drawing.warnings, id: \.self) { Text($0) }
                                Text("SHA-256")
                                Text(plan.file?.sha256 ?? "Неизвестно").font(.system(.caption, design: .monospaced))
                            }.font(.caption).textSelection(.enabled)
                        }
                    }.navigationTitle("Сведения о плане").toolbar { Button("Закрыть") { properties = false } }
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
