import Foundation

/// Priest & Hudson (1976), eq. 5; Brady & Brown (2004), eqs. 3.3–3.4.
/// Negative-exponential spacing assumption, not a measurement of an individual set.
enum PriestHudsonSpacing {
    static let version = "Priest-Hudson-1976/negative-exponential-bisection-v1"
    static func estimate(rqd: Double?) -> Double? {
        guard let rqd, rqd.isFinite, rqd > 0, rqd < 100 else { return nil }
        // Solve in x = 0.1 λ. log1p avoids overflow/underflow at small RQD.
        let target = rqd > 50 ? log1p((rqd - 100) / 100) : log(rqd) - log(100.0)
        var lo = 0.0, hi = 1.0
        while logFraction(hi) > target { hi *= 2 }
        for _ in 0..<160 {
            let mid = lo + (hi - lo) / 2
            if logFraction(mid) > target { lo = mid } else { hi = mid }
        }
        let sd = 0.1 / (lo + (hi - lo) / 2)
        return sd.isFinite && sd > 0 ? sd : nil
    }
    private static func logFraction(_ x: Double) -> Double {
        guard x < 0.001 else { return log1p(x) - x }
        // log(1+x)-x = -x²/2+x³/3-…; avoid cancellation near RQD=100%.
        var power = x * x, sum = 0.0
        for order in 2...12 {
            sum += (order.isMultiple(of: 2) ? -1 : 1) * power / Double(order)
            power *= x
        }
        return sum
    }

}

enum JointSpacingSource: String, Codable, Sendable { case estimatedFromRQD, manual, unknownLegacy
    var title: String {
        switch self { case .estimatedFromRQD: return "Оценка по RQD"; case .manual: return "Вручную"; case .unknownLegacy: return "Прежнее значение · источник неизвестен" }
    }
}
enum SpacingRQDSource: String, Codable, Sendable { case bartonQOriginal, rmr89Fallback }
struct SpacingRQD: Equatable, Sendable {
    let value: Double?
    let source: SpacingRQDSource?
    let evidence: String?
    let warning: String?
    init(q: BartonQInput, rmr: RMR89Input) {
        let hasQ = !q.rqd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRMR = !rmr.rqd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let a = try? RatingNumber.optional(q.rqd, name: "RQD", range: 0...100)
        let b = try? RatingNumber.optional(rmr.rqd, name: "RQD", range: 0...100)
        if hasQ && hasRMR && (a == nil || b == nil || a != b) {
            value = nil; source = nil; evidence = nil
            warning = "RQD в Q и RMR расходятся или некорректны. Уточните исходное RQD: автоматическая оценка SD недоступна."
        } else if hasQ {
            value = a; source = .bartonQOriginal
            evidence = [q.rqdSource?.rawValue, q.rqdEvidence].compactMap { $0 }.joined(separator: "; ")
            warning = a == nil ? "Исправьте исходное RQD в Barton Q." : nil
        } else {
            value = b; source = hasRMR ? .rmr89Fallback : nil; evidence = hasRMR ? rmr.rqdEvidence : nil
            warning = hasRMR ? "SD: используется исходное RQD из RMR89." : nil
        }
    }
}
struct JointSpacingProvenance: Codable, Equatable, Sendable {
    let source: JointSpacingSource
    let method: String
    let originalRQD: Double?
    let rqdSource: SpacingRQDSource?
    let rqdEvidence: String?
    static let manual = Self(source: .manual, method: "joint-spacing-entry-v1", originalRQD: nil, rqdSource: nil, rqdEvidence: nil)
    static func estimate(_ rqd: SpacingRQD) -> Self {
        Self(source: .estimatedFromRQD, method: PriestHudsonSpacing.version, originalRQD: rqd.value, rqdSource: rqd.source, rqdEvidence: rqd.evidence)
    }
    func validate(spacing: Double?) throws {
        switch source {
        case .estimatedFromRQD:
            guard method == PriestHudsonSpacing.version,
                  originalRQD.map({ $0.isFinite && (0...100).contains($0) && rqdSource != nil }) ?? true,
                  Self.matches(spacing, PriestHudsonSpacing.estimate(rqd: originalRQD)) else { throw StorageError.invalidRecord }
        case .manual:
            guard self == Self.manual else { throw StorageError.invalidRecord }
        case .unknownLegacy: throw StorageError.invalidRecord // represented by absent provenance on old records
        }
    }
    private static func matches(_ stored: Double?, _ expected: Double?) -> Bool {
        guard let stored, let expected else { return stored == nil && expected == nil }
        // libm can differ in its final bits between iPhone/iPad and simulator architectures.
        // Validate a saved result without rewriting it or requiring bit-identical transcendental math.
        return stored.isFinite && stored > 0 && abs(stored - expected) <= abs(expected) * 1e-12
    }

}
struct JointSpacingMean: Equatable, Sendable {
    let value: Double?
    let count: Int
    let includesEstimates: Bool
    init(_ sets: [InterpretedJointSet]) {
        let valid = sets.filter { $0.spacingMeters.map { $0.isFinite && $0 > 0 } ?? false }
        count = valid.count
        // Divide before summing to avoid overflowing an otherwise finite mean.
        value = valid.isEmpty ? nil : valid.reduce(0) { $0 + $1.spacingMeters! / Double(valid.count) }
        includesEstimates = valid.contains { $0.spacingProvenance?.source == .estimatedFromRQD }
    }
}

/// Numeric identifier kept as exact text (including leading zeroes), never a fabricated dictionary.
struct RockLithology: Codable, Equatable, Identifiable, Sendable {
    let code: String
    let name: String?
    var id: String { code }
    func validate() throws {
        guard code.range(of: "^[0-9]+(?:[.][0-9]+)?$", options: .regularExpression) != nil,
              name.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else {
            throw MappingError.invalid("ROCK: укажите числовой код и, при необходимости, название породы.")
        }
    }
}

/// Enterprise Appendix 6, Table 6; ISRM field grades. Intervals are estimates, not exact UCS.
enum FieldStrengthGrade: String, Codable, CaseIterable, Sendable {
    case R0, R1, R2, R3, R4, R5, R6
    static let version = "ISRM-R0-R6/enterprise-table6-v1"
    var rating: Int { [0, 1, 2, 4, 7, 12, 15][Self.allCases.firstIndex(of: self)!] }
    var interval: String { ["0,25–1", "1–5", "5–25", "25–50", "50–100", "100–250", ">250"][Self.allCases.firstIndex(of: self)!] }
    var recognition: String {
        switch self {
        case .R0: return "Крошится ногтем; ноготь оставляет вмятины"
        case .R1: return "Крошится остриём молотка; тонкий слой срезается ножом"
        case .R2: return "С трудом срезается ножом; остриё молотка оставляет неглубокие вмятины"
        case .R3: return "Нож не срезает; один точный удар молотка образует трещину"
        case .R4: return "Для образования трещины требуется более одного удара молотком"
        case .R5: return "Для разрушения требуется множество ударов молотком"
        case .R6: return "Повторные удары дают лишь сколы; порода звенит"
        }
    }
}
struct FieldStrengthAssessment: Codable, Equatable, Sendable {
    let grade: FieldStrengthGrade
    let rating: Int
    let method: String
    init(_ grade: FieldStrengthGrade) { self.grade = grade; rating = grade.rating; method = FieldStrengthGrade.version }
    func validate() throws { guard self == Self(grade) else { throw StorageError.invalidRecord } }
}

/// Bieniawski (1976), reproduced by Hoek, Carter & Diederichs (2013), Table 2.
/// Independent historical score; never added to RMR89 basic.
enum JCond76Category: String, Codable, CaseIterable, Sendable {
    case roughClosedHard, slightlyRoughHard, slightlyRoughSoft, slickensidedOrThinGouge, thickSoftGouge
    static let version = "Bieniawski-1976/JCond76-Hoek2013-table2-v1"
    var rating: Int { [25, 20, 12, 6, 0][Self.allCases.firstIndex(of: self)!] }
    var title: String {
        switch self {
        case .roughClosedHard: return "Очень шероховатые, прерывистые, сомкнутые; твёрдые стенки"
        case .slightlyRoughHard: return "Слегка шероховатые; раскрытие <1 мм; твёрдые стенки"
        case .slightlyRoughSoft: return "Слегка шероховатые; раскрытие <1 мм; мягкие стенки"
        case .slickensidedOrThinGouge: return "Зеркала скольжения / заполнитель <5 мм / раскрытие 1–5 мм; протяжённые"
        case .thickSoftGouge: return "Мягкий заполнитель >5 мм / раскрытие >5 мм; протяжённые"
        }
    }
}
struct JCond76Assessment: Codable, Equatable, Sendable {
    let category: JCond76Category
    let rating: Int
    let method: String
    init(_ category: JCond76Category) { self.category = category; rating = category.rating; method = JCond76Category.version }
    func validate() throws { guard self == Self(category) else { throw StorageError.invalidRecord } }
}
