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
        if case .failure(let error) = Result(catching: { try draft.validatedSpacing() }) {
            Text(error.localizedDescription).font(.caption).foregroundStyle(.red).accessibilityIdentifier("jointSpacingError")
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
    @State private var position: GSIChartPosition?
    @State private var information = false
    init(assessment: Binding<GSIAssessment?>) {
        _assessment = assessment
        _position = State(initialValue: assessment.wrappedValue?.chartPosition)
    }
    private var estimate: GSIChart.Estimate? { position.flatMap(GSIChart.estimate) }
    private var selectionText: String {
        if let estimate { return "GSI ≈ \(estimate.value)" }
        if let position { return GSIChart.categories(position) == nil ? "Неприменимо" : "За пределами контуров 5–95" }
        if let assessment { return "Ранее: \(EngineeringDisplay.number(assessment.lower))–\(EngineeringDisplay.number(assessment.upper)) · коснитесь диаграммы" }
        return "Коснитесь диаграммы"
    }
    var body: some View {
        VStack(spacing: 12) {
            GSIChartControl(position: $position)
            Text(selectionText).font(.title2.monospacedDigit()).accessibilityIdentifier("gsiSelectedValue")
            Button("Готово") {
                if let position, let record = try? GSIAssessment(position: position, assessedAt: (position == assessment?.chartPosition ? assessment?.assessedAt : nil) ?? Date()) {
                    assessment = record; dismiss()
                }
            }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                .disabled(estimate == nil).accessibilityIdentifier("confirmGSI")
        }.padding(.horizontal, 12).padding(.bottom, 12).frame(maxWidth: 760).frame(maxWidth: .infinity)
            .navigationTitle("GSI").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { information = true } label: { Label("Методика GSI", systemImage: "info.circle") } }
            .sheet(isPresented: $information) {
                NavigationStack {
                    List {
                        Text(GSIAssessment.reference)
                        Text("Численные линии извлечены из векторной таблицы 5.34, с. 126. Между соседними контурами используется локальная интерполяция; результат — целая оценка, не точное измерение. Крайние зоны за контурами 5 и 95 не экстраполируются.")
                        Text(GSIChart.version).font(.caption)
                        Text(GSIAssessment.limitation)
                        ForEach(GSIStructure.allCases, id: \.self) { Text($0.title + ": " + $0.detail) }
                        ForEach(GSISurface.allCases, id: \.self) { Text($0.title + ": " + $0.detail) }
                        if let assessment, assessment.chartPosition == nil {
                            Text("Прежняя категориальная оценка сохранена без переноса маркера: \(EngineeringDisplay.number(assessment.lower))–\(EngineeringDisplay.number(assessment.upper)).")
                        }
                        if assessment != nil { Button("Убрать оценку из черновика", role: .destructive) { assessment = nil; position = nil; information = false } }
                    }.navigationTitle("Методика").toolbar { Button("Закрыть") { information = false } }
                }
            }
    }
}

/// The plot itself owns a zero-distance drag; no enclosing scroll view competes for gestures.
private struct GSIChartControl: View {
    @Binding var position: GSIChartPosition?
    var body: some View {
        GeometryReader { geometry in
            let left = 88.0, top = 72.0
            let width = max(1, geometry.size.width-left-2), height = max(1, geometry.size.height-top-2)
            Canvas { context, _ in
                func point(_ p: GSIChartPosition) -> CGPoint { CGPoint(x: left+p.x*width, y: top+p.y*height) }
                func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                    CGRect(x: left+x*width, y: top+y*height, width: w*width, height: h*height)
                }
                let plot = CGRect(x: left, y: top, width: width, height: height)
                context.fill(Path(plot), with: .color(Color(uiColor: .secondarySystemBackground)))
                let sx = GSIChart.surfaceEdges, sy = GSIChart.structureEdges
                let invalid = [rect(sx[3], 0, 1-sx[3], sy[1]), rect(0, sy[5], sx[2], 1-sy[5])]
                for area in invalid {
                    context.fill(Path(area), with: .color(.secondary.opacity(0.2)))
                    context.draw(Text("N/A").font(.caption.bold()), at: CGPoint(x: area.midX, y: area.midY))
                }
                for (index, title) in ["Очень\nхорошее", "Хорошее", "Среднее", "Плохое", "Очень\nплохое"].enumerated() {
                    context.draw(Text(title).font(.system(size: 10, weight: .medium)),
                        at: CGPoint(x: left+(sx[index]+sx[index+1])/2*width, y: top-27))
                }
                context.draw(Text("Состояние поверхностей → хуже").font(.system(size: 10)), at: CGPoint(x: plot.midX, y: 12))
                let names = ["Массивный", "Блочный", "Сильно\nблочный", "Блочный /\nнарушенный /\nпрослои", "Раздроб-\nленный", "Слоистый /\nсдвиговый"]
                for (index, title) in names.enumerated() {
                    let cy = top+(sy[index]+sy[index+1])/2*height
                    context.draw(Text(title).font(.system(size: 10, weight: .medium)), at: CGPoint(x: 42, y: cy))
                }
                var grid = Path()
                for x in sx { grid.move(to: CGPoint(x: left+x*width, y: top)); grid.addLine(to: CGPoint(x: left+x*width, y: top+height)) }
                for y in sy { grid.move(to: CGPoint(x: left, y: top+y*height)); grid.addLine(to: CGPoint(x: left+width, y: top+y*height)) }
                context.stroke(grid, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)
                var valid = Path()
                valid.move(to: point(GSIChartPosition(x: 0, y: 0)))
                for p in [GSIChartPosition(x: sx[3], y: 0), GSIChartPosition(x: sx[3], y: sy[1]),
                          GSIChartPosition(x: 1, y: sy[1]), GSIChartPosition(x: 1, y: 1),
                          GSIChartPosition(x: sx[2], y: 1), GSIChartPosition(x: sx[2], y: sy[5]),
                          GSIChartPosition(x: 0, y: sy[5])] { valid.addLine(to: point(p)) }
                valid.closeSubpath()
                var lines = context; lines.clip(to: valid)
                for contour in GSIChart.contours {
                    var path = Path(); path.move(to: point(contour.a)); path.addLine(to: point(contour.b))
                    lines.stroke(path, with: .color(.primary.opacity(contour.value.isMultiple(of: 10) ? 0.9 : 0.4)), lineWidth: 1)
                    let label = CGPoint(x: (point(contour.a).x+point(contour.b).x)/2, y: (point(contour.a).y+point(contour.b).y)/2)
                    lines.fill(Path(roundedRect: CGRect(x: label.x-10, y: label.y-7, width: 20, height: 14), cornerRadius: 2), with: .color(Color(uiColor: .secondarySystemBackground)))
                    lines.draw(Text(String(contour.value)).font(.system(size: 10, weight: .semibold)), at: label)
                }
                context.stroke(Path(plot), with: .color(.primary), lineWidth: 1)
                if let position {
                    let p = point(position), color: Color = GSIChart.estimate(position) == nil ? .secondary : .orange
                    context.fill(Path(ellipseIn: CGRect(x: p.x-8, y: p.y-8, width: 16, height: 16)), with: .color(color))
                    context.stroke(Path(ellipseIn: CGRect(x: p.x-10, y: p.y-10, width: 20, height: 20)), with: .color(.white), lineWidth: 2)
                }
            }.overlay(alignment: .topLeading) {
                Color.clear.frame(width: width, height: height).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        if let next = GSIChartPosition.touch(x: value.location.x, y: value.location.y, width: width, height: height) { position = next }
                    }).offset(x: left, y: top).accessibilityIdentifier("gsiChart")
                    .accessibilityLabel("Диаграмма GSI: касание или перемещение маркера")
                    .accessibilityValue(position.map { "X \($0.x), Y \($0.y)" } ?? "Положение не выбрано")
            }
        }
    }
}
