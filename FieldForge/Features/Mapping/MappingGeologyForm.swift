import SwiftUI

extension ObservationPosition {
    var title: String {
        switch self { case .roof: return "Кровля"; case .leftWall: return "Левая стенка"; case .rightWall: return "Правая стенка"; case .face: return "Забой"; case .other: return "Другое" }
    }
}
extension TectonicStructureType {
    var title: String {
        switch self { case .fault: return "Разлом"; case .shearZone: return "Зона сдвига"; case .fractureZone: return "Зона трещиноватости"; case .other: return "Другое" }
    }
}

struct MappingIntervalForm: View {
    @Binding var start: String
    @Binding var end: String
    @Binding var position: ObservationPosition?
    let focus: FocusState<Bool>.Binding
    var startConvention = PicketConvention.tenMeters
    var endConvention = PicketConvention.tenMeters
    var body: some View {
        DisclosureGroup("Интервал и положение · необязательно") {
            GeologyField(title: "Начало интервала · пикет", text: $start, identifier: "mappingStartPicket",
                         error: picketError(start, field: "Начало", convention: startConvention), focus: focus)
            GeologyField(title: "Конец интервала · пикет", text: $end, identifier: "mappingEndPicket",
                         error: picketError(end, field: "Конец", convention: endConvention), focus: focus)
            if startConvention == .legacyMeters || endConvention == .legacyMeters {
                Text("Прежний формат интервала: метры или ПК км+метры.").font(.caption).foregroundStyle(.secondary)
            }
            if let a = try? startConvention.meters(start), let b = try? endConvention.meters(end), b < a {
                Text("Конец интервала должен быть не раньше начала.").font(.caption).foregroundStyle(.red)
            }
            Picker("Положение наблюдения", selection: $position) {
                Text("Не указано").tag(nil as ObservationPosition?)
                ForEach(ObservationPosition.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }.accessibilityIdentifier("mappingPosition")
            Text("Левая и правая стенка — по направлению возрастания пикетажа.")
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("mappingWallConvention")
            Text("Начало и конец — метры от того же начала и в том же направлении, что и основной пикет. Пустое поле остаётся неизвестным.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func picketError(_ text: String, field: String, convention: PicketConvention) -> String? {
        do { _ = try GeologyInput.optionalPicket(text, field: field, convention: convention); return nil } catch { return error.localizedDescription }
    }
}

struct MappingGeologyForm: View {
    @Binding var sets: [JointSetDraft]
    @Binding var structures: [TectonicStructureDraft]
    let measurements: [Measurement]
    let addSet: () -> Void
    var body: some View {
        Section {
            DisclosureGroup("Системы трещин: \(sets.count)/5") {
                Text("J1–J5 — ваши интерпретации, отдельно от исходных замеров. Представительные значения задаются вручную; усреднения и пересчёта севера нет.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($sets) { $set in
                    HStack {
                        NavigationLink { JointSetEditor(draft: $set, measurements: measurements) } label: {
                            VStack(alignment: .leading) {
                                Text("\(set.identifier.rawValue) · интерпретация")
                                GeologyOrientationSummary(input: set.representative)
                            }
                        }.accessibilityIdentifier("editJointSet-\(set.identifier.rawValue)")
                        Button(role: .destructive) { sets.removeAll { $0.id == set.id } } label: {
                            Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Удалить интерпретацию \(set.identifier.rawValue)")
                    }
                }
                Button("Добавить интерпретацию", action: addSet)
                    .disabled(sets.count >= 5).accessibilityIdentifier("addJointSet")
            }
        }
        MappingTectonicsForm(structures: $structures)
    }
}

struct MappingTectonicsForm: View {
    @Binding var structures: [TectonicStructureDraft]
    var body: some View {
        Section {
            DisclosureGroup("Тектоника: \(structures.count)") {
                ForEach($structures) { $structure in
                    HStack {
                        NavigationLink { TectonicStructureEditor(draft: $structure) } label: {
                            Text("№\((structures.firstIndex { $0.id == structure.id } ?? 0) + 1) · \(structure.type.title)")
                        }.accessibilityIdentifier("editTectonic-\(structure.id.uuidString)")
                        Button(role: .destructive) { structures.removeAll { $0.id == structure.id } } label: {
                            Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Удалить структуру из черновика")
                    }
                }
                Button("Добавить структуру") { structures.append(TectonicStructureDraft()) }
                    .accessibilityIdentifier("addTectonicStructure")
            }
        }
    }
}

private struct JointSetEditor: View {
    @Binding var draft: JointSetDraft
    let measurements: [Measurement]
    @FocusState private var focused: Bool
    var body: some View {
        Form {
            Section("Представительная ориентация · интерпретация") {
                GeologyOrientationForm(input: $draft.representative, focus: $focused)
            }
            Section("Ссылки на исходные замеры этой точки") {
                if measurements.isEmpty { Text("Исходные замеры не добавлены. Интерпретацию можно сохранить без ссылок.") }
                ForEach(Array(measurements.enumerated()), id: \.element.id) { index, reading in
                    Toggle(isOn: Binding(get: { draft.measurementIDs.contains(reading.id) }, set: { selected in
                        draft.measurementIDs.removeAll { $0 == reading.id }
                        if selected { draft.measurementIDs.append(reading.id) }
                    })) {
                        VStack(alignment: .leading) { Text("Замер №\(index + 1)"); MeasurementSummary(reading: reading) }
                    }.accessibilityIdentifier("jointEvidence-\(index + 1)")
                }
                Text("Ссылки обозначают исходные данные, в том числе с разным севером. Они не копируют ориентацию и не приводят её к общему северу. Удаление замера из черновика также убирает ссылки на него.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Полевые характеристики · необязательно") {
                GeologyField(title: "Расстояние между трещинами, м", text: $draft.spacing, identifier: "jointSpacing", nonnegative: true, focus: $focused)
                GeologyField(title: "Протяжённость, м", text: $draft.persistence, identifier: "jointPersistence", nonnegative: true, focus: $focused)
                GeologyField(title: "Раскрытие, мм", text: $draft.aperture, identifier: "jointAperture", nonnegative: true, focus: $focused)
                TextField("Шероховатость · описание, без рейтинга", text: $draft.roughness, axis: .vertical).focused($focused).accessibilityIdentifier("jointRoughness")
                TextField("Заполнитель · описание", text: $draft.infill, axis: .vertical).focused($focused).accessibilityIdentifier("jointInfill")
                TextField("Полевые примечания", text: $draft.notes, axis: .vertical).focused($focused).accessibilityIdentifier("jointNotes")
                TextField("Автор интерпретации", text: $draft.author).focused($focused).accessibilityIdentifier("jointAuthor")
            }
            Section { Text("Черновик. Интерпретация сохранится вместе с точкой по кнопке «Сохранить наблюдение».").font(.footnote) }
        }.navigationTitle(draft.identifier.rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false } } }
    }
}

struct TectonicStructureEditor: View {
    @Binding var draft: TectonicStructureDraft
    @FocusState private var focused: Bool
    var body: some View {
        Form {
            Section {
                Picker("Тип структуры", selection: $draft.type) {
                    ForEach(TectonicStructureType.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("tectonicType")
            }
            Section("Ориентировка · известные параметры") {
                GeologyOrientationForm(input: $draft.orientation, focus: $focused, permitsPartial: true)
            }
            Section {
                GeologyField(title: "Мощность, м", text: $draft.thickness, identifier: "tectonicThickness", nonnegative: true, focus: $focused)
                TextField("Описание · необязательно", text: $draft.description, axis: .vertical).focused($focused).accessibilityIdentifier("tectonicDescription")
            }
            DisclosureGroup("Отдельное положение структуры") {
                GeologyField(title: "Пикет · необязательно", text: $draft.picket, identifier: "tectonicPicket", error: picketError, focus: $focused)
                if draft.picketConvention == .legacyMeters {
                    Text("Прежний формат пикета: метры или ПК км+метры.").font(.caption).foregroundStyle(.secondary)
                } else if let confirmation = FieldPicketInput.confirmation(draft.picket) {
                    Text(confirmation).font(.caption).foregroundStyle(.secondary)
                }
                TextField("Положение · необязательно", text: $draft.position, axis: .vertical).focused($focused).accessibilityIdentifier("tectonicPosition")
            }
        }.navigationTitle("Тектоническая структура").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false } } }
    }
    private var picketError: String? {
        do { _ = try GeologyInput.optionalPicket(draft.picket, field: "Пикет структуры", convention: draft.picketConvention); return nil } catch { return error.localizedDescription }
    }
}

private struct GeologyOrientationForm: View {
    @Binding var input: ManualOrientationInput
    let focus: FocusState<Bool>.Binding
    var permitsPartial = false
    var body: some View {
        if permitsPartial, let error { orientationError(error) }
        GeologyField(title: "Азимут падения, °", text: $input.dipDirectionText, identifier: "geologyDirection", focus: focus)
        GeologyField(title: "Угол падения, °", text: $input.dipAngleText, identifier: "geologyDip", focus: focus)
        Picker("Север", selection: $input.reference) {
            ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("geologyNorth")
        if input.usesConventionalDipSide || Double(input.dipAngleText.replacingOccurrences(of: ",", with: ".")) == 90 {
            Toggle("Условная сторона вертикальной плоскости", isOn: $input.usesConventionalDipSide).accessibilityIdentifier("geologyConvention")
        }
        if !permitsPartial, let error { orientationError(error) }
    }
    private func orientationError(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red).accessibilityIdentifier("geologyOrientationError")
    }
    private var error: String? {
        do {
            if permitsPartial { _ = try input.validatedTectonic() } else { _ = try input.validated() }
            return nil
        } catch { return error.localizedDescription }
    }
}

/// Describes missing field data without presenting an incomplete plane as measured.
struct TectonicOrientationStatus: View {
    let input: ManualOrientationInput
    var body: some View {
        if let value = try? input.validatedTectonic() {
            if value.dipAngle == nil && value.dipDirection == nil {
                Text("Ориентировка не определена").font(.caption).foregroundStyle(.secondary)
            } else if value.dipAngle == nil {
                Text("Неполная ориентировка: угол падения не указан").font(.caption).foregroundStyle(.secondary)
            } else if value.dipDirection == nil {
                Text("Неполная ориентировка: азимут падения не определён").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct GeologyField: View {
    let title: String
    @Binding var text: String
    let identifier: String
    var error: String? = nil
    var nonnegative = false
    let focus: FocusState<Bool>.Binding
    private var validationError: String? {
        if let error { return error }
        guard nonnegative else { return nil }
        do { _ = try GeologyInput.optionalNonnegative(text, field: title); return nil } catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline)
            TextField("Не указано", text: $text).keyboardType(.numbersAndPunctuation).focused(focus).accessibilityIdentifier(identifier)
            if let validationError { Text(validationError).font(.caption).foregroundStyle(.red) }
        }
    }
}

struct GeologyOrientationSummary: View {
    let input: ManualOrientationInput
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let value = try? input.validated() {
                Text("Угол \(AngleText.format(value.orientation.dipAngle)) · азимут \(AngleText.format(value.orientation.dipDirection, azimuth: true))")
                Text("\(input.reference.title) · \(value.meaning.title)")
            } else { Text("Ориентация не заполнена или требует исправления") }
        }.font(.caption)
    }
}
