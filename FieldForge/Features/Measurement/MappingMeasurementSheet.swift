import SwiftUI

/// Original evidence remains local until the mapping workflow commits the whole point.
struct MappingMeasurementSheet: View {
    let automatic: Bool
    var addTitle = "Добавить замер"
    var representativeIssue: ((Measurement) -> String?)? = nil
    var onKeepOriginal: ((Measurement) throws -> Void)? = nil
    let onAdd: (Measurement) throws -> Void
    // Each presentation owns its sensor session. Root/standalone views cannot restart it.
    @StateObject private var model = AppModel(captureOnly: true)
    @Environment(\.scenePhase) private var scenePhase
    @State private var captureActive = false
    @Environment(\.dismiss) private var dismiss
    @State private var input = ManualOrientationInput()
    @State private var notes = ""
    @State private var error: String?
    @State private var added = false
    @FocusState private var notesFocused: Bool
    private var issue: String? { model.displayed.flatMap { representativeIssue?($0) } }
    private var canRecord: Bool { captureActive && !added && (automatic ? model.session.canSave : (try? input.validated()) != nil) }
    private var canAdd: Bool {
        canRecord && (!automatic || issue == nil)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if automatic { automaticContent }
                    else { ManualOrientationForm(input: $input, notes: $notes) }
                    Text("Замер будет добавлен в черновик точки. Сохраните точку кнопкой «Сохранить наблюдение».")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(automatic ? "Измерить iPhone" : "Ручной ввод")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { notesFocused = false; stopCapture(); dismiss() }.accessibilityIdentifier("closeMappingMeasurement") }
                if automatic {
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { notesFocused = false } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    HStack {
                        if automatic {
                            Button(model.isHeld ? "Повторить" : "Зафиксировать") { notesFocused = false; model.toggleHold() }
                                .buttonStyle(.bordered).disabled(!model.isHeld && !model.canHold)
                                .accessibilityIdentifier("mappingHold")
                        }
                        Button(addTitle) { add(using: onAdd) }
                            .buttonStyle(.borderedProminent).disabled(!canAdd)
                            .accessibilityIdentifier("addMappingMeasurement")
                    }
                    if automatic, issue != nil, let onKeepOriginal {
                        Button("Оставить только исходный замер") { add(using: onKeepOriginal) }
                            .disabled(!canRecord).accessibilityIdentifier("keepMappingOriginal")
                    }
                }.frame(maxWidth: .infinity).controlSize(.large).padding().background(.bar)
            }
        }
         .onAppear {
            captureActive = true
            if automatic {
                model.beginMappingCapture()
                model.setLifecycle(measurementVisible: true, foreground: scenePhase == .active)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if automatic { model.setLifecycle(measurementVisible: captureActive, foreground: phase == .active) }
        }
        .onDisappear { stopCapture() }
        .alert("Замер не добавлен", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Понятно", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func stopCapture() {
        captureActive = false
        if automatic { model.endMappingCapture() }
    }
    private var automaticContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.mock != nil {
                Label("DEMO · Синтетические данные", systemImage: "desktopcomputer").foregroundStyle(.orange)
            }
            Text(model.isHeld ? "ЗАФИКСИРОВАНО" : "ТЕКУЩЕЕ ИЗМЕРЕНИЕ").font(.caption.bold())
                .accessibilityIdentifier("mappingCaptureState")
            PlaneOrientationDial(orientation: model.displayed?.orientation)
                .frame(height: 250)
            HStack(alignment: .top, spacing: 12) {
                value("Угол падения, °", model.displayed?.orientation.dipAngle)
                value("Азимут падения, °", model.displayed?.orientation.dipDirection, azimuth: true)
            }
            Text("Азимут: 0° — север, 90° — восток, по часовой стрелке.").font(.caption).foregroundStyle(.secondary)
            if let reading = model.displayed {
                Text("\(reading.reference.title) · \(reading.source.title)").font(.subheadline)
                Label(reading.quality.title, systemImage: "info.circle").foregroundStyle(reading.quality.color)
                Text(reading.explanation).font(.footnote)
                Text("Калибровка: \(reading.sample?.magneticAccuracy.title ?? "—"); точность не подтверждена.").font(.caption)
                Text(MeasurementDateText.format(reading.timestamp, detailed: true)).font(.caption).monospacedDigit()
                if let issue {
                    Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("jointRepresentativeIssue")
                }
            } else {
                Label("Измерение недоступно", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Повторить получение данных") { model.acquisition.reset() }
                    .disabled(scenePhase != .active)
            }
            Text(model.sensorStatus).font(.caption).accessibilityIdentifier("mappingSensorStatus")
            Text("Плоскость измерения — экран iPhone. Выступ камеры и чехол не гарантируют плоский контакт. Требуется проверка геологическим компасом.").font(.footnote).foregroundStyle(.secondary)
            if model.isHeld {
                TextField("Примечание к измерению", text: $model.notes, axis: .vertical).textFieldStyle(.roundedBorder)
                    .focused($notesFocused)
            }
            #if DEBUG
            if model.mock != nil {
                Picker("Сценарий DEMO", selection: Binding(get: { model.mock?.condition ?? .normal }, set: {
                    model.updateMock(dip: 45, direction: 90, condition: $0)
                })) {
                    ForEach(MockCondition.allCases) { Text($0.title).tag($0) }
                }.disabled(model.isHeld).accessibilityIdentifier("mappingMockCondition")
            }
            #endif
        }
    }
    private func value(_ label: String, _ number: Double?, azimuth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            Text(AngleText.format(number, azimuth: azimuth))
                .font(.system(size: 40, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func add(using accept: (Measurement) throws -> Void) {
        guard canRecord else { return }
        notesFocused = false
        do {
            let reading: Measurement
            if automatic {
                guard let frozen = model.session.record(notes: model.notes) else { return }
                reading = frozen
            } else { reading = try input.observation(notes: notes) }
            try accept(reading)
            added = true
            if automatic { model.session.markSaved() }
            stopCapture(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Schematic plane seen from above in the reading's north frame, not phone heading.
/// Ellipse flattening illustrates dip; its minor axis and arrow point downhill.
struct PlaneOrientationDial: View {
    let orientation: PlaneOrientation?
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(.quaternary)
                Circle().stroke(.secondary.opacity(0.4), lineWidth: 2)
                Text("С").offset(y: -size * 0.43)
                Text("Ю").offset(y: size * 0.43)
                Text("В").offset(x: size * 0.43)
                Text("З").offset(x: -size * 0.43)
                if let dip = orientation?.dipAngle, let direction = orientation?.dipDirection {
                    ZStack {
                        Ellipse().fill(Color.accentColor.opacity(0.2))
                            .overlay(Ellipse().stroke(Color.accentColor, lineWidth: 2))
                            .frame(width: size * 0.68, height: max(2, size * 0.68 * cos(dip * .pi / 180)))
                        Image(systemName: "arrow.up").font(.system(size: size * 0.32, weight: .bold))
                            .foregroundStyle(Color.accentColor).offset(y: -size * 0.11)
                    }.rotationEffect(.degrees(direction))
                } else {
                    VStack { Text("—").font(.largeTitle); Text("Азимут недоступен").font(.caption) }
                }
            }.font(.caption.bold()).frame(width: size, height: size).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Плоскость: угол \(AngleText.format(orientation?.dipAngle)); направление вниз \(AngleText.format(orientation?.dipDirection, azimuth: true))")
    }
}

struct MeasurementSummary: View {
    let reading: Measurement
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Угол \(AngleText.format(reading.orientation.dipAngle)) · азимут \(AngleText.format(reading.orientation.dipDirection, azimuth: true))").monospacedDigit()
            Text("\(reading.source.title) · \(reading.reference.title)").font(.caption)
            Text(MeasurementDateText.format(reading.timestamp, detailed: true)).font(.caption).monospacedDigit()
            Text(reading.quality.title).font(.caption).foregroundStyle(reading.quality.color)
        }.padding(.vertical, 2)
    }
}
