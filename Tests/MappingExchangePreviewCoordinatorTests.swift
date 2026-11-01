import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

/// Noncooperative dependencies deliberately finish after cancellation. Arrivals and
/// releases are continuation-driven; no sleeps, polling or timing-based race setup.
@MainActor private final class PreviewGate<Value: Sendable> {
    private var pending: [Int: CheckedContinuation<Value, Error>] = [:]
    private var arrivals: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var cancelledOnReturn: [Int: Bool] = [:]
    func value(_ id: Int) async throws -> Value {
        do {
            let value = try await withCheckedThrowingContinuation { continuation in
                precondition(pending[id] == nil)
                pending[id] = continuation
                for arrival in arrivals.removeValue(forKey: id) ?? [] { arrival.resume() }
            }
            cancelledOnReturn[id] = Task.isCancelled
            return value
        } catch {
            cancelledOnReturn[id] = Task.isCancelled
            throw error
        }
    }
    func arrived(_ id: Int) async {
        if pending[id] != nil { return }
        await withCheckedContinuation { arrivals[id, default: []].append($0) }
    }
    func succeed(_ id: Int, _ value: Value) { pending.removeValue(forKey: id)!.resume(returning: value) }
    func fail(_ id: Int) { pending.removeValue(forKey: id)!.resume(throwing: ExchangeImportError("Late failure \(id)")) }
}

@MainActor final class MappingExchangePreviewCoordinatorTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/unused/synthetic.xlsx")
    private func result(_ snapshot: MappingCommittedSnapshot, _ label: String) -> MappingExchangePreview {
        .init(workbookID: UUID(), generationID: snapshot.generationID,
              exportedAt: Date(timeIntervalSinceReferenceDate: 0), projectName: label,
              metadata: [:], records: [], proposalDigest: label)
    }
    private func work(_ snapshot: MappingCommittedSnapshot, reads: PreviewGate<MappingExchangePreview>, id: Int,
                      freshness: PreviewGate<Bool>? = nil) -> MappingExchangePreviewCoordinator.Work {
        .init(snapshot: { snapshot }, read: { _, _ in try await reads.value(id) },
              isCurrent: { _ in if let freshness { return try await freshness.value(id) }; return true })
    }
    private func screen(_ snapshot: MappingCommittedSnapshot) -> MappingExchangePreviewCoordinator {
        let coordinator = MappingExchangePreviewCoordinator(); coordinator.activate(generation: snapshot.generationID); return coordinator
    }
    func testACompletesAfterBOnlyBPublishes() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0)))
        await reads.arrived(0)
        let b = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 1)))
        await reads.arrived(1)
        reads.succeed(1, result(snapshot, "B")); await b.task.value
        let publication = coordinator.state.publicationID
        reads.succeed(0, result(snapshot, "A")); await a.task.value
        XCTAssertEqual(coordinator.state.preview?.projectName, "B")
        XCTAssertEqual(coordinator.state.publicationID, publication)
        XCTAssertFalse(coordinator.state.busy); XCTAssertFalse(coordinator.state.stale); XCTAssertNil(coordinator.state.message)
    }
    func testACompletesWhileBPendingOldDeferAndCancellationMessageCannotChangeBusy() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0)))
        await reads.arrived(0)
        let b = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 1)))
        await reads.arrived(1)
        reads.succeed(0, result(snapshot, "A")); await a.task.value
        XCTAssertTrue(coordinator.state.busy); XCTAssertNil(coordinator.state.preview); XCTAssertNil(coordinator.state.message)
        XCTAssertEqual(coordinator.operationID, b.id)
        reads.succeed(1, result(snapshot, "B")); await b.task.value
        XCTAssertEqual(coordinator.state.preview?.projectName, "B")
    }
    func testUserCancellationRevokesPublicationImmediatelyDespiteLateRead() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0)))
        await reads.arrived(0)
        coordinator.cancel(operationID: a.id)
        let message = coordinator.state.message
        XCTAssertFalse(coordinator.state.busy); XCTAssertNil(coordinator.operationID)
        reads.succeed(0, result(snapshot, "A")); await a.task.value
        XCTAssertNil(coordinator.state.preview); XCTAssertEqual(coordinator.state.message, message)
        XCTAssertEqual(reads.cancelledOnReturn[0], true)
    }
    func testCancellingOldAHandleDoesNotCancelB() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0)))
        await reads.arrived(0)
        coordinator.cancel(operationID: a.id)
        let b = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 1)))
        await reads.arrived(1)
        coordinator.cancel(operationID: a.id) // A stale button/callback must not cancel B.
        reads.succeed(0, result(snapshot, "A")); await a.task.value
        XCTAssertTrue(coordinator.state.busy); XCTAssertNil(coordinator.state.message)
        reads.succeed(1, result(snapshot, "B")); await b.task.value
        XCTAssertEqual(reads.cancelledOnReturn[1], false)
        XCTAssertEqual(coordinator.state.preview?.projectName, "B")
    }
    func testOldReadFailureCannotReplaceNewSuccess() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0)))
        await reads.arrived(0)
        let b = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 1)))
        await reads.arrived(1)
        reads.succeed(1, result(snapshot, "B")); await b.task.value
        reads.fail(0); await a.task.value
        XCTAssertEqual(coordinator.state.preview?.projectName, "B"); XCTAssertNil(coordinator.state.message)
    }
    func testLateSnapshotFailureCannotFinishNewOperation() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), snapshots = PreviewGate<MappingCommittedSnapshot>(), reads = PreviewGate<MappingExchangePreview>(), coordinator = screen(snapshot)
        let aWork = MappingExchangePreviewCoordinator.Work(snapshot: { try await snapshots.value(0) }, read: { _, _ in XCTFail("Revoked snapshot must never start a reader"); throw CancellationError() }, isCurrent: { _ in true })
        let a = try XCTUnwrap(coordinator.prepare(url, work: aWork)); await snapshots.arrived(0)
        let b = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 1))); await reads.arrived(1)
        snapshots.fail(0); await a.task.value
        XCTAssertTrue(coordinator.state.busy); XCTAssertNil(coordinator.state.message)
        reads.succeed(1, result(snapshot, "B")); await b.task.value
        XCTAssertEqual(coordinator.state.preview?.projectName, "B")
    }
    func testFreshnessCompletesBeforePublicationAndChangedGenerationIsStale() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), freshness = PreviewGate<Bool>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0, freshness: freshness)))
        await reads.arrived(0); reads.succeed(0, result(snapshot, "A")); await freshness.arrived(0)
        XCTAssertNil(coordinator.state.preview); XCTAssertTrue(coordinator.state.busy)
        freshness.succeed(0, false); await a.task.value
        XCTAssertEqual(coordinator.state.preview?.projectName, "A"); XCTAssertTrue(coordinator.state.stale); XCTAssertFalse(coordinator.state.busy)
    }
    func testJournalNotificationDuringFreshnessCannotBeOverwrittenByEarlierTrueRead() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), freshness = PreviewGate<Bool>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0, freshness: freshness)))
        await reads.arrived(0); reads.succeed(0, result(snapshot, "A")); await freshness.arrived(0)
        coordinator.journalChanged(to: UUID())
        freshness.succeed(0, true); await a.task.value
        XCTAssertTrue(coordinator.state.stale)
    }
    func testOldFreshnessFailureCannotAffectNewPreview() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), freshness = PreviewGate<Bool>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0, freshness: freshness)))
        await reads.arrived(0); reads.succeed(0, result(snapshot, "A")); await freshness.arrived(0)
        let b = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 1))); await reads.arrived(1)
        reads.succeed(1, result(snapshot, "B")); await b.task.value
        freshness.fail(0); await a.task.value
        XCTAssertEqual(coordinator.state.preview?.projectName, "B"); XCTAssertFalse(coordinator.state.stale); XCTAssertNil(coordinator.state.message)
    }
    func testLeavingScreenRevokesLatePublicationAndReopeningCanStartAgain() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0))); await reads.arrived(0)
        coordinator.deactivate()
        XCTAssertFalse(coordinator.state.busy); XCTAssertFalse(coordinator.isActive)
        XCTAssertNil(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 9)))
        reads.succeed(0, result(snapshot, "A")); await a.task.value
        XCTAssertNil(coordinator.state.preview); XCTAssertNil(coordinator.state.message)
        coordinator.activate(generation: snapshot.generationID)
        let b = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 1))); await reads.arrived(1)
        reads.succeed(1, result(snapshot, "B")); await b.task.value
        XCTAssertEqual(coordinator.state.preview?.projectName, "B")
    }
    func testPeriodicMonitorIdentityProtectsNewPublicationOfSameGeneration() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), monitor = PreviewGate<Bool>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0))); await reads.arrived(0)
        reads.succeed(0, result(snapshot, "A")); await a.task.value
        let publication = try XCTUnwrap(coordinator.state.publicationID)
        let oldMonitor = Task { await coordinator.refresh(publication) { _ in try await monitor.value(0) } }
        await monitor.arrived(0)
        let b = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 1))); await reads.arrived(1)
        reads.succeed(1, result(snapshot, "B")); await b.task.value
        monitor.fail(0); await oldMonitor.value
        XCTAssertNotEqual(publication, coordinator.state.publicationID)
        XCTAssertEqual(coordinator.state.preview?.projectName, "B"); XCTAssertFalse(coordinator.state.stale)
    }
    func testMonitorFromClosedAppearanceCannotPublishAfterReopeningSamePreview() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), monitor = PreviewGate<Bool>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0))); await reads.arrived(0)
        reads.succeed(0, result(snapshot, "A")); await a.task.value
        let publication = try XCTUnwrap(coordinator.state.publicationID)
        let oldMonitor = Task { await coordinator.refresh(publication) { _ in try await monitor.value(0) } }
        await monitor.arrived(0)
        coordinator.deactivate(); coordinator.activate(generation: snapshot.generationID)
        monitor.succeed(0, false); await oldMonitor.value // No reliance on SwiftUI task cancellation.
        XCTAssertFalse(coordinator.state.stale)
        let newMonitor = Task { await coordinator.refresh(publication) { _ in try await monitor.value(1) } }
        await monitor.arrived(1); monitor.succeed(1, false); await newMonitor.value
        XCTAssertTrue(coordinator.state.stale)
    }
    func testCancelledMonitorAndEarlierTrueReadCannotClearOrCreateStaleness() async throws {
        let snapshot = MappingCommittedSnapshot(MappingJournal()), reads = PreviewGate<MappingExchangePreview>(), monitor = PreviewGate<Bool>(), coordinator = screen(snapshot)
        let a = try XCTUnwrap(coordinator.prepare(url, work: work(snapshot, reads: reads, id: 0))); await reads.arrived(0)
        reads.succeed(0, result(snapshot, "A")); await a.task.value
        let publication = try XCTUnwrap(coordinator.state.publicationID)
        let cancelled = Task { await coordinator.refresh(publication) { _ in try await monitor.value(0) } }
        await monitor.arrived(0); cancelled.cancel(); monitor.succeed(0, false); await cancelled.value
        XCTAssertFalse(coordinator.state.stale)
        let earlier = Task { await coordinator.refresh(publication) { _ in try await monitor.value(1) } }
        await monitor.arrived(1); coordinator.journalChanged(to: UUID()); monitor.succeed(1, true); await earlier.value
        XCTAssertTrue(coordinator.state.stale)
    }
}
