import SwiftUI

struct MeasurementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mockDip = 45.0
    @State private var mockDirection = 90.0
    @State private var mockCondition = MockCondition.normal
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Способ измерения", selection: Binding(get: { model.mode }, set: model.setMode)) {
                    ForEach(MeasurementMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("measurementMode")
                if model.mode == .manual {
                    ManualEntryView()
                } else {
                    automaticContent
                }
            }.padding()
        }
        .navigationTitle("Измерение")
        .onAppear { model.measurementScreenVisibilityChanged(true) }
        .onDisappear { model.measurementScreenVisibilityChanged(false) }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if model.mode == .manual {
                    if model.savedManual != nil {
                        Button("Новое измерение", action: model.newManualObservation)
                            .buttonStyle(.bordered).accessibilityIdentifier("newManualButton")
                    }
                    Button(action: model.saveManual) {
                        Label(model.savedManual == nil ? "Сохранить" : "Сохранено", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(!model.canSaveManual)
                        .accessibilityIdentifier("saveManualButton")
                } else {
                    Button(action: model.toggleHold) {
                        Label(model.isHeld ? "Продолжить" : "HOLD", systemImage: model.isHeld ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).disabled(!model.isHeld && !model.canHold)
                        .accessibilityIdentifier("holdButton")
                    Button(action: model.saveFrozen) {
                        Label(model.session.hasSavedFrozen ? "Сохранено" : "Сохранить", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(!model.canSave)
                        .accessibilityIdentifier("saveButton")
                }
            }.controlSize(.large).padding().background(.bar)
        }
    }
    private var automaticContent: some View {
        Group {
            if model.mock != nil {
                Label("DEMO · Синтетические данные", systemImage: "desktopcomputer")
                    .font(.headline).foregroundStyle(.orange)
                    .accessibilityIdentifier("mockBanner")
            }
            Text(model.isHeld ? "ЗАФИКСИРОВАНО · HOLD" : "ТЕКУЩЕЕ ИЗМЕРЕНИЕ")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                indicator("Азимут падения", value: model.displayed?.orientation.dipDirection, azimuth: true)
                indicator("Угол падения", value: model.displayed?.orientation.dipAngle)
            }
            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 20) {
                CompassView(direction: model.displayed?.orientation.dipDirection)
                InclinationView(dip: model.displayed?.orientation.dipAngle)
            }.frame(height: 180)
            if let measurement = model.displayed {
                Label(measurement.quality.title, systemImage: "exclamationmark.circle")
                    .font(.headline).foregroundStyle(measurement.quality.color)
                Text(measurement.explanation).font(.subheadline)
                LabeledContent("Опора", value: measurement.reference.title)
                LabeledContent("Источник", value: measurement.source.title)
                Text("Магнитная калибровка: \(measurement.sample?.magneticAccuracy.title ?? "—"). Даже высокая оценка не исключает помех.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Измерение недоступно", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Text(model.sensorStatus).font(.caption).foregroundStyle(.secondary)
            Text("Плоскость измерения: экран iPhone").font(.subheadline)
            if model.isHeld {
                TextField("Примечание к измерению", text: $model.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder).disabled(model.session.hasSavedFrozen)
            }
            if model.mock != nil { mockControls }
            Text("Экспериментальный прототип. Для инженерных решений требуется проверка геологическим компасом.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func indicator(_ title: String, value: Double?, azimuth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(AngleText.format(value, azimuth: azimuth)).font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var mockControls: some View {
        GroupBox("Сценарий симулятора") {
            VStack {
                Picker("Угол", selection: $mockDip) {
                    ForEach([0.0, 0.2, 30, 45, 60, 89.8, 90], id: \.self) { Text(AngleText.format($0)).tag($0) }
                }
                Picker("Азимут", selection: $mockDirection) {
                    ForEach([0.0, 0.1, 45, 90, 180, 270, 359.9], id: \.self) {
                        Text(AngleText.format($0, azimuth: true)).tag($0)
                    }
                }
                Picker("Состояние", selection: $mockCondition) {
                    ForEach(MockCondition.allCases) { Text($0.title).tag($0) }
                }
            }.disabled(model.isHeld)
            .onChange(of: mockDip) { _, _ in updateMock() }
            .onChange(of: mockDirection) { _, _ in updateMock() }
            .onChange(of: mockCondition) { _, _ in updateMock() }
        }
    }
    private func updateMock() { model.updateMock(dip: mockDip, direction: mockDirection, condition: mockCondition) }
}

struct CompassView: View {
    let direction: Double?
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().stroke(.secondary.opacity(0.3), lineWidth: 2)
                Text("С").offset(y: -size * 0.39)
                Text("Ю").offset(y: size * 0.39)
                Text("В").offset(x: size * 0.39)
                Text("З").offset(x: -size * 0.39)
                if let direction {
                    Image(systemName: "arrow.up").font(.system(size: size * 0.45, weight: .light))
                        .foregroundStyle(Color("AccentColor")).rotationEffect(.degrees(direction))
                } else { Text("—").font(.largeTitle).foregroundStyle(.secondary) }
            }.font(.caption.weight(.semibold)).frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Компас: \(AngleText.format(direction, azimuth: true))")
    }
}

struct InclinationView: View {
    let dip: Double?
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                if let dip {
                    Capsule().fill(Color("AccentColor")).frame(height: 4).rotationEffect(.degrees(dip))
                }
            }.frame(width: 90, height: 90)
            Text("Наклон плоскости").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
            .accessibilityLabel("Наклон: \(AngleText.format(dip))")
    }
}
