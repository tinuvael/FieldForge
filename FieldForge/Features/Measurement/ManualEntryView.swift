import SwiftUI

struct ManualEntryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ManualOrientationForm(input: $model.manualInput, notes: $model.manualNotes, saved: model.savedManual != nil)
            .onChange(of: model.manualInput) { _, _ in model.manualDraftChanged() }
            .onChange(of: model.manualNotes) { _, _ in model.manualDraftChanged() }
    }
}

struct ManualOrientationForm: View {
    @Binding var input: ManualOrientationInput
    @Binding var notes: String
    var saved = false
    private var validationMessage: String? {
        do { _ = try input.validated(); return nil } catch { return error.localizedDescription }
    }
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
                TextField("Например, 45", text: $input.dipAngleText)
                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .dip).accessibilityIdentifier("manualDip")
                Text("Азимут падения · 0–360°")
                TextField("Например, 270; пусто — не определён", text: $input.dipDirectionText)
                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .direction).accessibilityIdentifier("manualDirection")
            }
            Text("При 0° оставьте азимут пустым. При 90° можно оставить его пустым или явно выбрать условную сторону падения.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Азимут — условная сторона вертикальной плоскости", isOn: $input.usesConventionalDipSide)
                .accessibilityIdentifier("manualConvention")
            Picker("Вид севера", selection: $input.reference) {
                ForEach(GeographicReference.manualChoices, id: \.self) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("manualNorth")
            TextField("Примечание (необязательно)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder).focused($focusedField, equals: .notes)
                .accessibilityIdentifier("manualNotes")
            if let message = validationMessage {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            } else if let result = try? input.validated() {
                Label("Ввод проверен", systemImage: "checkmark.circle").foregroundStyle(Color("AccentColor"))
                    .accessibilityIdentifier("manualValidated")
                Text("Азимут \(AngleText.format(result.orientation.dipDirection, azimuth: true)) · угол \(AngleText.format(result.orientation.dipAngle))")
                if result.meaning == .conventionalDipSide {
                    Text("Условная сторона, а не однозначное направление вниз.").font(.footnote)
                }
            }
            if saved {
                Label("Запись добавлена в журнал", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("manualSaved")
            }
            Text("Ручная запись не содержит данных Core Motion. Введённые значения и выбранный север не подтверждают точность прибора.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focusedField = nil }
            }
        }
    }
}
