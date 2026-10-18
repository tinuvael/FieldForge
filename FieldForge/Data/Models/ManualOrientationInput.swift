import Foundation

enum ManualEntryError: LocalizedError {
    case dipAngle, dipDirection, horizontalDirection, missingDirection, verticalConvention, northReference
    var errorDescription: String? {
        switch self {
        case .dipAngle: return "Введите угол падения от 0 до 90° числом."
        case .dipDirection: return "Введите азимут от 0 до 360° числом."
        case .horizontalDirection: return "Для горизонтальной плоскости оставьте азимут пустым."
        case .missingDirection: return "Для наклонной плоскости укажите азимут падения."
        case .verticalConvention: return "Для вертикальной плоскости подтвердите условную сторону падения или оставьте азимут пустым."
        case .northReference: return "Выберите магнитный, истинный, сеточный или неизвестный север."
        }
    }
}

/// Original field text is retained, including 360° and decimal-comma spelling.
struct ManualOrientationInput: Codable, Equatable, Sendable {
    var dipAngleText = ""
    var dipDirectionText = ""
    var reference = GeographicReference.unknown
    var usesConventionalDipSide = false

    private func number(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value.isFinite else { return nil }
        return value
    }

    func validated() throws -> (orientation: PlaneOrientation, meaning: DipDirectionMeaning) {
        guard let dip = number(dipAngleText), (0...90).contains(dip) else { throw ManualEntryError.dipAngle }
        guard GeographicReference.manualChoices.contains(reference) else { throw ManualEntryError.northReference }
        let hasDirection = !dipDirectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let direction = number(dipDirectionText)
        if hasDirection {
            guard let direction, (0...360).contains(direction) else { throw ManualEntryError.dipDirection }
        }
        if dip == 0 && hasDirection { throw ManualEntryError.horizontalDirection }
        if dip > 0 && dip < 90 && !hasDirection { throw ManualEntryError.missingDirection }
        if usesConventionalDipSide && (dip != 90 || !hasDirection) { throw ManualEntryError.verticalConvention }
        if dip == 90 && hasDirection && !usesConventionalDipSide { throw ManualEntryError.verticalConvention }
        let status: CalculationStatus = dip == 0 ? .horizontalAmbiguity : dip == 90 ? .verticalAmbiguity : .valid
        return (PlaneOrientation(dipAngle: dip, dipDirection: direction.map { $0 == 360 ? 0 : $0 },
                                 status: status, normal: nil),
                !hasDirection ? .undefined : dip == 90 ? .conventionalDipSide : .downhill)
    }

    func observation(notes: String = "", id: UUID = UUID(), timestamp: Date = Date()) throws -> Measurement {
        let result = try validated()
        return Measurement(id: id, timestamp: timestamp, orientation: result.orientation,
                           reference: reference, quality: .manualUnverified, sample: nil, notes: notes,
                           plane: "geologicalPlane", algorithmVersion: "manual-entry-v1",
                           source: .manualCompass, directionMeaning: result.meaning, manualInput: self)
    }

    /// Tectonic descriptions may retain independent, missing angle components.
    /// Incomplete input never produces a PlaneOrientation or a measured observation.
    /// The stored text/north/convention fields and their Codable representation are unchanged.
    func validatedTectonic() throws -> (dipAngle: Double?, dipDirection: Double?) {
        let hasDip = !dipAngleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDirection = !dipDirectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let dip = number(dipAngleText), direction = number(dipDirectionText)
        if hasDip {
            guard let dip, (0...90).contains(dip) else { throw ManualEntryError.dipAngle }
        }
        if hasDirection {
            guard let direction, (0...360).contains(direction) else { throw ManualEntryError.dipDirection }
        }
        guard GeographicReference.manualChoices.contains(reference) else { throw ManualEntryError.northReference }
        if hasDip && hasDirection {
            _ = try validated() // Preserve complete horizontal/vertical and conventional-side rules.
        } else if usesConventionalDipSide {
            throw ManualEntryError.verticalConvention
        }
        return (dip, direction)
    }
}
