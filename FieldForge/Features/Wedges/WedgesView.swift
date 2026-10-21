import SwiftUI

struct WedgesView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var axisText = ""
    @State private var axisFocused = false
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
    private enum InputField: Hashable { case width, height, length }
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
                geometrySection
                jointsSection
                sceneSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Клинья")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if axisFocused || focusedField != nil {
                    HStack {
                        Spacer()
                        Button("Готово") { axisFocused = false; focusedField = nil }
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .accessibilityIdentifier("wedgesKeyboardDone")
                    }
                    .padding(.horizontal, 16).frame(height: 52)
                    .background(.bar).overlay(alignment: .top) { Divider() }
                }
            }
            .onDisappear { axisFocused = false; focusedField = nil }
            .onChange(of: focusedField) { _, value in if value != nil { axisFocused = false } }
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
                Text("Азимут оси, °")
                Spacer()
                LosslessNumericField(text: Binding(get: { axisText }, set: { axisText = $0; axisEdited = true }),
                    displayText: WedgeInput.azimuth(axisText).map { EngineeringDisplay.orientationInput($0) + "°" } ?? axisText,
                    focused: axisFocused, identifier: "wedgeAxis", placeholder: "Не задан",
                    keyboard: .decimalPad, alignment: .right, nativeDone: false) { active in
                        axisFocused = active
                        if active { focusedField = nil }
                    }.frame(maxWidth: 110)
            }
            .contentShape(Rectangle()).onTapGesture { axisFocused = true; focusedField = nil }
            Button("Замерить ось") { axisFocused = false; focusedField = nil; headingPresented = true }
            Picker("Север оси", selection: Binding(get: { axisNorth }, set: { axisNorth = $0; axisEdited = true })) {
                ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
            }
            if axisNorth == .gridNorth {
                Text("Проверьте, что ось и системы заданы в одной сетке координат. Идентификатор сетки отсутствует в исходных ориентировках.").font(.caption).foregroundStyle(.orange)
            }
            if let capture = axisCapture {
                DisclosureGroup(axisEdited ? "Исходный замер оси · изменён вручную" : "Сведения о замере оси") {
                    Text("\(capture.sample.timestamp.formatted()) · \(EngineeringDisplay.number(capture.azimuth, decimals: 1))° · калибровка высокая")
                    Text("Поле \(EngineeringDisplay.number(capture.sample.magneticField.length, decimals: 1)) мкТл. Магнитные помехи не исключены.")
                }.font(.caption)
            }
            if !axisText.isEmpty, WedgeInput.azimuth(axisText) == nil { Text("Азимут: 0–360°").font(.caption).foregroundStyle(.orange) }
            dimensionRow("Ширина B, м", input: $width, target: .width)
            dimensionRow("Высота H, м", input: $height, target: .height)
            HStack {
                Text("Длина L, м")
                TextField("Не задана", text: $length).keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing).focused($focusedField, equals: .length)
            }
            switch dimensions {
            case .success: EmptyView()
            case .failure(let error):
                if !width.text.isEmpty && !height.text.isEmpty && !length.isEmpty {
                    Text(error.localizedDescription).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
    private func dimensionRow(_ title: String, input: Binding<WedgeDimensionInput>, target: DimensionTarget) -> some View {
            HStack {
                Text(title)
                TextField("Не задана", text: Binding(get: {
                    let field: InputField = target == .width ? .width : .height
                    if !input.wrappedValue.manuallyEdited, focusedField != field, let result = input.wrappedValue.measurement {
                        return EngineeringDisplay.number(result.metres, decimals: 2)
                    }
                    return input.wrappedValue.text
                }, set: { input.wrappedValue.edit($0) }))
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: target == .width ? .width : .height)
                    .multilineTextAlignment(.trailing)
                Button("LiDAR") { axisFocused = false; focusedField = nil; distanceTarget = target }.buttonStyle(.borderless)
            }
    }
    private var jointsSection: some View {
        Section("Системы трещин") {
            if let workflow = mapping.workflow {
                Text(contextTitle(workflow)).font(.caption).foregroundStyle(.secondary)
            }
            Picker("Наблюдение картирования", selection: $sourceID) {
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
                Text("Выбрано: \(selected.count) из 3").font(.caption)
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
                DisclosureGroup("Допущения модели") {
                    Text("LiDAR: приблизительные размеры; точность не проверена.")
                    Text("Свод: \(DistanceMath.text(value.archHeight)); стенка: \(DistanceMath.text(value.wallHeight))")
                    if let result = width.measurement { Text("Исходная ширина: \(result.text)\(width.manuallyEdited ? " · исправлено вручную" : "")") }
                    if let result = height.measurement { Text("Исходная высота: \(result.text)\(height.manuallyEdited ? " · исправлено вручную" : "")") }
                    Text("W1: прямая горизонтальная выработка; параметры не сохраняются. H — от почвы до вершины свода; временно f ≤ 12, подъём B/3. f — коэффициент Протодъяконова.")
                    Text("X — вправо, Y — вдоль оси, Z — вверх; метры. Ось направлена по возрастанию пикетажа. Азимуты по часовой стрелке от выбранного севера.")
                    Text("Плоскости проходят через условный центр. Положение, протяжённость и окончания трещин неизвестны. Конечный клин и механическая устойчивость не определены.")
                }.font(.caption)
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
