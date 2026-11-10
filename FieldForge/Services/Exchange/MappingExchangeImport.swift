import Foundation
import CryptoKit

enum MappingExchangeImport {
    struct Selection: Sendable {
        var accepted: Set<String> = []
        var rejectedPending: Set<String> = []
        var rejectedConflicts: Set<String> = []
    }

    struct Result: Identifiable, Sendable {
        enum Status: String, CaseIterable, Sendable {
            case applied, alreadyApplied, unchanged, skipped, rejected, pending, notProcessed
            var title: String {
                switch self {
                case .applied: "Импортировано"
                case .alreadyApplied: "Импортировано ранее"
                case .unchanged: "Без изменений"
                case .skipped: "Пропущено"
                case .rejected: "Отклонено"
                case .pending: "Ожидает продолжения"
                case .notProcessed: "Не обработано"
                }
            }
        }
        let id: String
        let label: String
        let status: Status
        let detail: String
    }

    struct Report: Sendable {
        let rows: [Result]
        let interrupted: Bool
        func count(_ status: Result.Status) -> Int { rows.count { $0.status == status } }
    }

    struct Item: Sendable {
        enum Action: Sendable {
            case execute(MappingImportOperation, MappingObservation?)
            case rejectPending(MappingImportOperation)
            case report(Result.Status, String)

            var operation: MappingImportOperation? {
                switch self {
                case .execute(let op, _), .rejectPending(let op): op
                case .report: nil
                }
            }
        }
        let record: MappingExchangePreview.Record
        let action: Action

        func reconciling(_ entry: MappingImportLedger.Entry?) throws -> Action {
            guard let entry, let op = action.operation, op.isMutation,
                  entry.operation.source == op.source, entry.operation.sourceRecordID == op.sourceRecordID,
                  entry.operation.kind == op.kind, entry.operation.target == op.target else { return action }
            switch entry.outcome {
            case .applied: return .report(.alreadyApplied, "")
            case .skipped: return .report(.skipped, "")
            case .rejected(let conflict): return .report(.rejected, conflict.exchangeMessage ?? record.reason)
            case .pending:
                if case .rejectPending = action { return action }
                guard let date = entry.operation.correction?.date ?? entry.operation.creationDate else { throw StorageError.invalidRecord }
                return try MappingExchangeImport.mutation(record, source: op.source, now: date, pending: entry.operation)
            }
        }

        func result(_ status: Result.Status, _ detail: String = "") -> Result {
            let label = [record.label, record.location].filter { !$0.isEmpty }.joined(separator: " · ")
            return Result(id: record.id, label: label, status: status, detail: detail)
        }

        func result(for outcome: MappingImportOutcome) -> Result {
            switch outcome {
            case .applied: result(.applied)
            case .skipped: result(.skipped)
            case .pending: result(.pending, "Выберите ту же книгу, чтобы продолжить или отклонить строку.")
            case .rejected(let conflict): result(.rejected, conflict.exchangeMessage ?? record.reason)
            }
        }
    }

    struct Batch: Sendable {
        let source: MappingImportSource
        let items: [Item]

        init(preview: MappingExchangePreview, bytes: Data, selection: Selection, now: Date) throws {
            guard !preview.workbookBlocked, let expected = preview.source else {
                throw ExchangeImportError("Эту книгу нельзя импортировать. Проверьте ошибки на защищённых листах.")
            }
            source = MappingImportSource(kind: .exchange, documentID: expected.documentID, bytes: bytes)
            guard source == expected else { throw ExchangeImportError("Файл изменился после проверки. Выберите книгу и проверьте её снова.") }
            items = try preview.records.map { record in
                Item(record: record, action: try MappingExchangeImport.action(record, source: expected, selection: selection, now: now))
            }
        }
    }

    private static func action(_ record: MappingExchangePreview.Record, source: MappingImportSource,
                               selection: Selection, now: Date) throws -> Item.Action {
        let receipt = record.receipt
        if receipt?.outcome == .applied { return .report(.alreadyApplied, "") }
        if let receipt, case .rejected(let conflict) = receipt.outcome {
            return .report(.rejected, conflict.exchangeMessage ?? "Предыдущее решение об отклонении сохранено.")
        }
        let pending = receipt?.outcome == .pending ? receipt?.operation : nil
        if let pending, selection.rejectedPending.contains(record.id) { return .rejectPending(pending) }

        if selection.accepted.contains(record.id), record.canApply {
            return try mutation(record, source: source, now: now, pending: pending)
        }
        if pending != nil { return .report(.pending, "Предыдущий импорт прерван. Продолжите или отклоните эту строку.") }

        switch record.classification {
        case .unchanged: return .report(.unchanged, "")
        case .duplicate: return .report(.skipped, record.reason)
        case .unsupported, .invalid: return .report(.rejected, record.reason)
        case .conflict:
            guard selection.rejectedConflicts.contains(record.id), let target = record.target else { return .report(.rejected, record.reason) }
            return .execute(try operation(.conflict, for: record, target: target, source: source, note: "Конфликт обнаружен при проверке книги."), nil)
        case .new, .correction:
            guard let target = record.target else { throw StorageError.invalidRecord }
            return .execute(try operation(.skip, for: record, target: target, source: source), nil)
        }
    }

    private static func mutation(_ record: MappingExchangePreview.Record, source: MappingImportSource,
                                 now: Date, pending: MappingImportOperation?) throws -> Item.Action {
        guard let proposed = record.proposed, record.graphFingerprint != nil else { throw StorageError.invalidRecord }
        let kind: MappingImportOperation.Kind = record.classification == .new ? .create : .update
        let date = pending?.correction?.date ?? pending?.creationDate ?? now
        let proposal = try finalized(proposed, previous: record.previous, date: date)
        let correction = kind == .update ? MappingImportOperation.Correction(date: date,
            author: record.correctionAuthor, reason: record.correctionReason) : nil
        let op = try operation(kind, for: record, target: MappingImportTarget(proposal), source: source,
            proposal: proposal, correction: correction)
        guard pending == nil || pending == op else {
            throw ExchangeImportError("Не удалось восстановить исходное предложение. Отклоните незавершённую строку или выберите исходный файл.")
        }
        return .execute(op, proposal)
    }

    private static func operation(_ kind: MappingImportOperation.Kind, for record: MappingExchangePreview.Record,
                                  target: MappingImportTarget, source: MappingImportSource, proposal: MappingObservation? = nil,
                                  correction: MappingImportOperation.Correction? = nil, note: String? = nil) throws -> MappingImportOperation {
        // Decision-specific identity lets a skipped row be selected in a later confirmation.
        // A terminal rejection of an approved mutation is retained for this exact file.
        let key = try MappingExchangeExport.json(["exchange-stage-4b", source.documentID, source.fingerprint, record.id, kind.rawValue])
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                             bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return try MappingImportOperation(id: id, source: source, sourceRecordID: record.id, target: target, kind: kind,
            baseline: kind == .update ? record.baseline : nil, proposal: proposal,
            graphFingerprint: proposal == nil ? nil : record.graphFingerprint, correction: correction, note: note)
    }

    private static func finalized(_ point: MappingObservation, previous: MappingObservation?, date: Date) throws -> MappingObservation {
        let geology: MappingGeology?
        if let current = point.geology {
            let oldSets = Dictionary(uniqueKeysWithValues: (previous?.geology?.jointSets ?? []).map { ($0.id, $0) })
            let sets = try current.jointSets.map { set -> InterpretedJointSet in
                guard let old = oldSets[set.id], old != set else { return set }
                guard old.revision < Int.max else { throw StorageError.invalidRecord }
                return InterpretedJointSet(id: set.id, identifier: set.identifier, revision: old.revision + 1,
                    interpretedAt: date, author: set.author, method: set.method, representative: set.representative,
                    measurementIDs: set.measurementIDs, spacingMeters: set.spacingMeters, persistenceMeters: set.persistenceMeters,
                    apertureMillimeters: set.apertureMillimeters, roughness: set.roughness, infill: set.infill,
                    notes: set.notes, spacingProvenance: set.spacingProvenance)
            }
            geology = MappingGeology(start: current.start, end: current.end, position: current.position,
                jointSets: sets, tectonicStructures: current.tectonicStructures)
        } else { geology = nil }
        return MappingObservation(id: point.id, projectID: point.projectID, horizonID: point.horizonID, excavationID: point.excavationID,
            picket: point.picket, chainageMeters: point.chainageMeters, chainageOriginAndDirection: point.chainageOriginAndDirection,
            observedAt: point.observedAt, observedTimeZoneID: point.observedTimeZoneID, observedUTCOffsetSeconds: point.observedUTCOffsetSeconds,
            createdAt: previous?.createdAt ?? date, updatedAt: previous?.updatedAt ?? date, coordinates: point.coordinates,
            measurementIDs: point.measurementIDs, notes: point.notes, geology: geology, ratings: point.ratings,
            picketConvention: point.picketConvention, rock: point.rock)
    }
}

private extension MappingImportConflict {
    var exchangeMessage: String? {
        switch self {
        case .revisionChanged, .observationChanged, .contextChanged, .ownershipChanged:
            "Точка, её версия или контекст изменились. Выгрузите книгу заново."
        case .targetExists, .revisionIDInUse, .duplicateSourceRecord:
            "Строка или её идентификатор уже использованы."
        case .targetMissing: "Точка отсутствует в журнале."
        case .sourceChanged, .operationIDReused, .proposalChanged:
            "Книга или предложение изменились. Проверьте файл снова."
        case .invalidProposal: "Предложение не прошло итоговую проверку журнала."
        case .protectedEvidence: "Предложение затрагивает защищённые данные."
        case .previewConflict: nil
        }
    }
}
