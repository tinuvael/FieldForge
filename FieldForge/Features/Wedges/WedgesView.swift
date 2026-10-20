import SwiftUI

struct WedgesView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var axisText = ""
    @State private var axisNorth = GeographicReference.unknown
    @State private var axisCapture: WedgeAxisCapture?
    @State private var axisEdited = true
    @State private var width = WedgeDimensionInput()
    @State private var height = WedgeDimensionInput()
    @State private var length = ""
    @State private var sourceID: UUID?
    @State private var selected: Set<UUID> = []
    @State private var headingPresented = false
    @State private var distanceTarget: DimensionTarget?
    @FocusState private var focusedField: InputField?
    private enum InputField: Hashable { case axis, width, height, length }
    private enum DimensionTarget: String, Identifiable { case width, height; var id: String { rawValue } }
    private var sources: [WedgeMappingSource] { mapping.workflow.map(WedgeMappingSource.available) ?? [] }
    private var source: WedgeMappingSource? { sources.first { $0.id == sourceID } }
    private var dimensions: Result<WedgeDimensions, Error> {
        Result {
            guard let b = WedgeInput.number(width.text), let h = WedgeInput.number(height.text), let l = WedgeInput.number(length) else {
                throw MappingError.invalid("Введите ширину B, полную высоту H и длину L в метрах.")
            }
            return try WedgeDimensions(width: b, height: h, length: l)
        }
    }
    private var jointResult: Result<[WedgeJoint], Error> {
        Result {
            guard let source else { throw MappingError.invalid("Выберите наблюдение картирования: текущий черновик или сохранённую точку в активной выработке.") }
            return try source.selectedJoints(selected, axisNorth: axisNorth)
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("W1 · параметры и модель не сохраняются").font(.subheadline)
                    Text("Прямая горизонтальная выработка. Схема ориентировок, без оценки устойчивости.").font(.caption).foregroundStyle(.secondary)
                }
                geometrySection
                jointsSection
                sceneSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Клинья")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { focusedField = nil }.accessibilityIdentifier("wedgesKeyboardDone")
                }
            }
            .onDisappear { focusedField = nil }
            .sheet(isPresented: $headingPresented) {
                WedgeHeadingSheet { capture in
                    axisText = String(capture.azimuth); axisNorth = .magneticNorth
                    axisCapture = capture; axisEdited = false
                }
            }
            .fullScreenCover(item: $distanceTarget) { target in
                DistanceMeasurementSheet(closeReturnsResult: false) { result in
                    if target == .width { width.accept(result) } else { height.accept(result) }
                }
            }
            .onChange(of: source) { _, value in selected = value?.initialSelection ?? [] }
        }
    }
    private var geometrySection: some View {
        Section("Геометрия выработки") {
            HStack {
                TextField("Азимут оси, °", text: Binding(get: { axisText }, set: { axisText = $0; axisEdited = true }))
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .axis)
                Button("Замерить ось") { focusedField = nil; headingPresented = true }.buttonStyle(.bordered)
            }
            Picker("Север оси", selection: Binding(get: { axisNorth }, set: { axisNorth = $0; axisEdited = true })) {
                ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
            }
            if axisNorth == .gridNorth {
                Text("Проверьте, что ось и системы заданы в одной сетке координат. Идентификатор сетки отсутствует в исходных ориентировках.").font(.caption).foregroundStyle(.orange)
            }
            Text(axisEdited ? "Ось: ручной ввод · 0–360°, по ходу увеличения пикетажа" : "Ось: датчики iPhone · магнитный север · точность не проверена")
                .font(.caption).foregroundStyle(.secondary)
            if let capture = axisCapture {
                DisclosureGroup(axisEdited ? "Исходный замер оси · изменён вручную" : "Сведения о замере оси") {
                    Text("\(capture.sample.timestamp.formatted()) · \(EngineeringDisplay.number(capture.azimuth, decimals: 1))° · калибровка высокая")
                    Text("Поле \(EngineeringDisplay.number(capture.sample.magneticField.length, decimals: 1)) мкТл. Магнитные помехи не исключены.")
                }.font(.caption)
            }
            if WedgeInput.azimuth(axisText) == nil { Text("Укажите азимут оси от 0 до 360°.").font(.caption).foregroundStyle(.orange) }
            dimensionRow("Ширина B, м", input: $width, target: .width)
            dimensionRow("Полная высота H, м", input: $height, target: .height)
            TextField("Длина L, м · вручную", text: $length).keyboardType(.decimalPad)
                .focused($focusedField, equals: .length)
            Text("H — от почвы до вершины свода. Временно: f ≤ 12, подъём B/3. f — коэффициент Протодъяконова, не UCS и не RMR.")
                .font(.caption).foregroundStyle(.secondary)
            switch dimensions {
            case .success(let value):
                Text("Свод: \(DistanceMath.text(value.archHeight)); стенка: \(DistanceMath.text(value.wallHeight))").font(.caption)
            case .failure(let error): Text(error.localizedDescription).font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private func dimensionRow(_ title: String, input: Binding<WedgeDimensionInput>, target: DimensionTarget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(title, text: Binding(get: { input.wrappedValue.text }, set: { input.wrappedValue.edit($0) }))
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: target == .width ? .width : .height)
                Button("LiDAR") { focusedField = nil; distanceTarget = target }.buttonStyle(.bordered)
            }
            if let result = input.wrappedValue.measurement {
                Text("\(result.text)\(input.wrappedValue.manuallyEdited ? " · исправлено вручную" : " · измерено"). Приблизительно, точность не проверена.")
                    .font(.caption).foregroundStyle(.secondary)
            } else { Text("Ручной ввод").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var jointsSection: some View {
        Section("Системы трещин") {
            if let workflow = mapping.workflow {
                Text(contextTitle(workflow)).font(.caption).foregroundStyle(.secondary)
            }
            Picker("Источник Mapping", selection: $sourceID) {
                Text("Выберите наблюдение").tag(nil as UUID?)
                ForEach(sources) { item in Text(item.title).tag(Optional(item.id)) }
            }
            if sources.isEmpty { Text("Выберите проект, горизонт и выработку во вкладке «Картирование».").font(.caption) }
            if let source {
                DisclosureGroup("UUID и ревизия источника") {
                    Text(source.pointID.uuidString)
                    if let version = source.version {
                        Text("Версия \(version) · \(source.revisionID?.uuidString ?? "исходная запись")")
                    } else { Text("Несохранённый черновик; постоянной ревизии нет.") }
                }.font(.caption).textSelection(.enabled)
                ForEach(source.joints) { joint in
                    Button {
                        if selected.contains(joint.id) { selected.remove(joint.id) } else { selected.insert(joint.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(joint.id) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(joint.identifier.rawValue)
                                Text(jointLabel(joint)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!joint.orientationValid)
                }
                Text("Выбрано: \(selected.count) из 3. Только интерпретированные системы, исходные замеры не подставляются.").font(.caption)
            }
            if case .failure(let error) = jointResult { Text(error.localizedDescription).font(.caption).foregroundStyle(.orange) }
        }
    }
    private var sceneSection: some View {
        Section("3D-модель") {
            if case .success(let value) = dimensions {
                WedgeSceneView(dimensions: value, planes: scenePlanes, axisAzimuth: WedgeInput.azimuth(axisText))
                    .frame(height: 350).listRowInsets(EdgeInsets())
                    .accessibilityLabel("Трёхцентровая выработка и схематические плоскости. Вращение пальцем, масштаб двумя пальцами.")
                Text("Вращение пальцем · масштаб двумя пальцами").font(.caption)
                Text("X — вправо, Y — вдоль оси, Z — вверх; метры. Азимуты по часовой стрелке от указанного севера.").font(.caption)
                if !scenePlanes.isEmpty {
                    Text("Все плоскости проходят через условный центр модели. Линии — их схематические пересечения; положения, протяжённость и окончания трещин неизвестны. Реальный конечный клин не определён.").font(.caption)
                }
            } else { Text("Заполните допустимые B, H и L для построения выработки.") }
        }
    }
    private var scenePlanes: [WedgeScenePlane] {
        guard let axis = WedgeInput.azimuth(axisText), case .success(let joints) = jointResult else { return [] }
        return joints.compactMap { joint in
            WedgePlaneGeometry.normal(input: joint.input, axis: axis).map { WedgeScenePlane(identifier: joint.identifier.rawValue, normal: $0) }
        }
    }
    private func jointLabel(_ joint: WedgeJoint) -> String {
        guard joint.orientationValid else { return "Неполная ориентировка: проверьте угол, направление и условную сторону для 90°." }
        return "Падение \(joint.input.dipAngleText)° / \(joint.input.dipDirectionText.isEmpty ? "—" : joint.input.dipDirectionText + "°") · \(joint.input.reference.title)"
    }
    private func contextTitle(_ w: MappingWorkflow) -> String {
        let project = w.journal.projects.first { $0.id == w.context.projectID }?.name ?? "Проект не выбран"
        let excavation = w.excavations.first { $0.id == w.context.excavationID }?.name ?? "Выработка не выбрана"
        return "\(project) / \(w.selectedHorizon?.displayName ?? "Горизонт не выбран") / \(excavation)"
    }
}
