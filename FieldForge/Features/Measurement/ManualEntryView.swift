import SwiftUI

struct ManualEntryView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focusedField: Field?
    private enum Field { case direction, dip, notes }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Ручной ввод · геологический компас", systemImage: "pencil.and.list.clipboard")
                .font(.headline)
            Text("Перенесите показания компаса. Вид севера сохраняется без пересчёта.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Угол падения · 0–90°")
                TextField("Например, 45", text: $model.manualInput.dipAngleText)
                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .dip).accessibilityIdentifier("manualDip")
                Text("Азимут падения · 0–360°")
                TextField("Например, 270; пусто — не определён", text: $model.manualInput.dipDirectionText)
                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .direction).accessibilityIdentifier("manualDirection")
            }
            Text("При 0° оставьте азимут пустым. При 90° можно оставить его пустым или явно выбрать условную сторону падения.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Азимут — условная сторона вертикальной плоскости", isOn: $model.manualInput.usesConventionalDipSide)
                .accessibilityIdentifier("manualConvention")
            Picker("Вид севера", selection: $model.manualInput.reference) {
                ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("manualNorth")
            TextField("Примечание (необязательно)", text: $model.manualNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder).focused($focusedField, equals: .notes)
                .accessibilityIdentifier("manualNotes")
            if let message = model.manualValidationMessage {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            } else if let result = try? model.manualInput.validated() {
                Label("Ввод проверен", systemImage: "checkmark.circle").foregroundStyle(Color("AccentColor"))
                    .accessibilityIdentifier("manualValidated")
                Text("Азимут \(AngleText.format(result.orientation.dipDirection, azimuth: true)) · угол \(AngleText.format(result.orientation.dipAngle))")
                if result.meaning == .conventionalDipSide {
                    Text("Условная сторона, а не однозначное направление вниз.").font(.footnote)
                }
            }
            if model.savedManual != nil {
                Label("Запись добавлена в журнал", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("manualSaved")
            }
            Text("Ручная запись не содержит данных Core Motion. Введённые значения и выбранный север не подтверждают точность прибора.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: model.manualInput) { _, _ in model.manualDraftChanged() }
        .onChange(of: model.manualNotes) { _, _ in model.manualDraftChanged() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focusedField = nil }
            }
        }
    }
}
