import SwiftUI

struct JointSpacingField: View {
    @Binding var draft: JointSetDraft
    let rqd: SpacingRQD
    @State private var focused = false
    var body: some View {
        HStack {
            Text("SD, м")
            LosslessNumericField(text: $draft.spacing,
                displayText: (try? RatingNumber.optional(draft.spacing, name: "SD")).map { EngineeringDisplay.number($0, decimals: 2) } ?? draft.spacing,
                focused: focused, identifier: "jointSpacing", placeholder: "Не указано", keyboard: .decimalPad, alignment: .right,
                onFocus: { focused = $0 }).frame(minHeight: 44)
        }
        HStack {
            Text((draft.spacingProvenance?.source ?? .unknownLegacy).title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if draft.spacingProvenance?.source != .estimatedFromRQD {
                Button("Оценить по RQD") { draft.resetSpacingEstimate(rqd) }
                    .font(.caption).accessibilityIdentifier("resetJointSpacing")
            }
        }
        if let warning = rqd.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
    }
}

struct RockLithologyField: View {
    @Binding var rock: RockLithology?
    let projectID: UUID
    @EnvironmentObject private var mapping: MappingModel
    private var dictionary: [RockLithology] { mapping.workflow?.journal.projects.first { $0.id == projectID }?.lithologies ?? [] }
    var body: some View {
        Section {
            Picker("ROCK", selection: Binding(get: { rock?.code ?? "" }, set: { code in rock = dictionary.first { $0.code == code } })) {
                Text("Не указан").tag("")
                ForEach(dictionary) { item in Text(item.code + (item.name.map { " · " + $0 } ?? "")).tag(item.code) }
                if let rock, !dictionary.contains(where: { $0.code == rock.code }) { Text(rock.code).tag(rock.code) }
            }.accessibilityIdentifier("mappingROCK")
            NavigationLink("Коды пород проекта") { LithologyDictionaryEditor(projectID: projectID) }
        }
    }
}
private struct LithologyDictionaryEditor: View {
    let projectID: UUID
    @EnvironmentObject private var mapping: MappingModel
    @State private var code = ""
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        Form {
            Section("Справочник проекта") {
                ForEach(mapping.workflow?.journal.projects.first { $0.id == projectID }?.lithologies ?? []) { rock in
                    LabeledContent(rock.code, value: rock.name ?? "Без названия")
                }
                Text("Коды добавляются по принятому справочнику предприятия. Сохранённые коды и названия наблюдений остаются неизменными.").font(.caption)
            }
            Section("Добавить код") {
                TextField("Числовой код ROCK", text: $code).keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("rockCode")
                TextField("Название · необязательно", text: $name).focused($focused).accessibilityIdentifier("rockName")
                Button("Добавить") {
                    do {
                        let rock = RockLithology(code: code.trimmingCharacters(in: .whitespacesAndNewlines), name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name)
                        guard mapping.workflow != nil else { throw StorageError.writesBlocked }
                        try mapping.workflow!.addLithology(rock, projectID: projectID)
                        code = ""; name = ""; error = nil; focused = false
                    } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("addRockCode")
                if let error { Text(error).foregroundStyle(.red) }
            }
        }.navigationTitle("Коды ROCK").scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false } } }
    }
}

struct GSISelectionView: View {
    @Binding var assessment: GSIAssessment?
    @Environment(\.dismiss) private var dismiss
    @State private var selection: GSIChartSelection?
    @State private var lower = ""
    @State private var upper = ""
    @State private var finalValue = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    init(assessment: Binding<GSIAssessment?>) {
        _assessment = assessment
        _selection = State(initialValue: assessment.wrappedValue?.selection)
        _lower = State(initialValue: assessment.wrappedValue.map { ElevationInput.text($0.lower) } ?? "")
        _upper = State(initialValue: assessment.wrappedValue.map { ElevationInput.text($0.upper) } ?? "")
        _finalValue = State(initialValue: assessment.wrappedValue?.finalValue.map(ElevationInput.text) ?? "")
    }
    var body: some View {
        Form {
            Section("Структура × состояние поверхности") {
                Text("Выберите ячейку. Столбцы 1–5: от очень хорошего до очень плохого состояния.").font(.caption)
                // Five >=44 pt targets fit a compact iPhone; full descriptions remain below.
                VStack(alignment: .leading, spacing: 12) {
                    Text("1 · Очень хорошее; 2 · Хорошее; 3 · Среднее; 4 · Плохое; 5 · Очень плохое").font(.caption)
                    ForEach(GSIStructure.allCases, id: \.self) { structure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(structure.title).font(.subheadline)
                            HStack(spacing: 4) {
                                ForEach(Array(GSISurface.allCases.enumerated()), id: \.element) { index, surface in
                                    let point = GSIChartSelection(structure: structure, surface: surface)
                                    Button { selection = point; error = nil } label: {
                                        HStack(spacing: 2) {
                                            Text(String(index + 1))
                                            Image(systemName: selection == point ? "checkmark.circle.fill" : point.applicable ? "circle" : "nosign").font(.caption)
                                        }.frame(minWidth: 44, minHeight: 44).frame(maxWidth: .infinity)
                                            .background(selection == point ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                    }.buttonStyle(.plain).disabled(!point.applicable)
                                        .accessibilityLabel(structure.title + ", " + surface.title + (point.applicable ? "" : ", неприменимо"))
                                        .accessibilityIdentifier("gsiCell-\(structure.rawValue)-\(surface.rawValue)")
                                }
                            }
                        }
                    }
                }
                if let selection {
                    Text(selection.structure.title + " · " + selection.surface.title).font(.headline).accessibilityIdentifier("gsiSelectedCell")
                    Text(selection.structure.detail).font(.caption)
                    Text(selection.surface.detail).font(.caption)
                }
            }
            Section("GSI · интервал выбирает инженер") {
                Text("Числовые контуры не оцифрованы. Ячейка не вычисляет GSI; укажите обоснованный интервал явно.").font(.caption)
                TextField("Нижняя граница, 0…100", text: $lower).keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("gsiLower")
                TextField("Верхняя граница, 0…100", text: $upper).keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("gsiUpper")
                TextField("Уточнённый GSI · необязательно", text: $finalValue).keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("gsiFinal")
                if let error { Text(error).foregroundStyle(.red) }
                Button("Подтвердить GSI") {
                    do { assessment = try record(); focused = false; dismiss() } catch { self.error = error.localizedDescription }
                }.disabled((try? record()) == nil).accessibilityIdentifier("confirmGSI")
                if assessment != nil { Button("Удалить оценку из черновика", role: .destructive) { assessment = nil; dismiss() } }
            }
            DisclosureGroup("Категории и методика") {
                ForEach(Array(GSIStructure.allCases.enumerated()), id: \.element) { index, item in Text("\(index + 1). \(item.title): \(item.detail)") }
                ForEach(Array(GSISurface.allCases.enumerated()), id: \.element) { index, item in Text("\(index + 1). \(item.title): \(item.detail)") }
                Text(GSIAssessment.reference)
                Text(GSIAssessment.limitation)
                Text("GSI — геологическая оценка. Рекомендации по устойчивости и крепи не формируются. Корреляции с Q, RMR и JCond76 не применяются.")
            }.font(.caption)
        }.navigationTitle("GSI").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false } } }
    }
    private func record() throws -> GSIAssessment {
        guard let selection,
              let a = try RatingNumber.optional(lower, name: "Нижняя граница GSI", range: 0...100),
              let b = try RatingNumber.optional(upper, name: "Верхняя граница GSI", range: 0...100) else { throw MappingError.invalid("Выберите ячейку и интервал GSI.") }
        let result = GSIAssessment(selection: selection, lower: a, upper: b,
            finalValue: try RatingNumber.optional(finalValue, name: "GSI", range: 0...100), assessedAt: Date())
        try result.validate(); return result
    }
}
