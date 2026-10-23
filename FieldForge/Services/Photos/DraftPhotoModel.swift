import Foundation

struct DraftPhotoSession: Equatable {
    let id: UUID
    let context: PhotoContext
}

extension MappingModel {
    func beginDraftPhotos() throws -> DraftPhotoSession {
        guard let w = workflow, !w.draft.saving,
              let p = w.context.projectID, let h = w.context.horizonID, let e = w.context.excavationID else {
            throw MappingError.invalid("Сначала выберите проект, горизонт и выработку.")
        }
        let session = DraftPhotoSession(id: UUID(), context: PhotoContext(projectID: p, horizonID: h, excavationID: e,
            pointID: w.draft.id, pointRevisionID: w.draft.id, pointVersion: 1, locationBasis: .unknownBeforeFirstSave))
        workflow!.draft.photoSessions.insert(session.id)
        return session
    }
    func endDraftPhotos(_ session: DraftPhotoSession) {
        guard workflow?.draft.id == session.context.pointID else { return }
        workflow!.draft.photoSessions.remove(session.id)
    }
    private func accepts(_ session: DraftPhotoSession) -> Bool {
        guard let w = workflow else { return false }
        return !w.draft.saving && w.draft.id == session.context.pointID && w.draft.photoSessions.contains(session.id) &&
            w.context.projectID == session.context.projectID && w.context.horizonID == session.context.horizonID
    }
    func receiveDraftPhoto(_ received: ReceivedPhoto, session: DraftPhotoSession) async {
        guard accepts(session), let files = photoStore else { return }
        do {
            let operation = try await storage.run {
                try files.makeOperation(data: received.data, filename: received.filename, context: session.context,
                    source: received.source, representation: received.representation, captureWallTime: received.captureWallTime,
                    captureUTCOffset: received.captureUTCOffset, captureSubseconds: received.captureSubseconds)
            }
            // Both checks are necessary: discard can occur while ImageIO is validating.
            guard accepts(session) else { return }
            retainedPhotos[operation.id] = RetainedPhotoImport(operation: operation, data: received.data)
            workflow!.draft.photos.append(operation)
        } catch { if accepts(session) { photoError = "Изображение не принято: \(error.localizedDescription)" } }
    }
    func removeDraftPhoto(_ id: UUID, draftID: UUID) {
        guard workflow?.draft.id == draftID, workflow?.draft.saving == false else { return }
        workflow!.draft.photos.removeAll { $0.id == id }
        retainedPhotos.removeValue(forKey: id)
        // An earlier failed Save may have written files. Retain them for reviewed recovery.
        Task { await refreshPhotoRecovery() }
    }
    func draftPhotoData(_ operation: PhotoImportOperation) async throws -> Data {
        if let retained = retainedPhotos[operation.id] { return retained.data }
        guard let files = photoStore else { throw StorageError.writesBlocked }
        return try await storage.run { try files.read(operation.attachment) }
    }
    func saveDraft(id: UUID) async {
        guard let w = workflow, w.draft.id == id else { return } // already committed identity: idempotent retry
        guard !isSaving, !photoBusy else { error = "Дождитесь завершения сохранения и повторите действие."; return }
        let operations = w.draft.photos, retained = retainedPhotos, files = photoStore
        do {
            try await persist { next in
                guard next.draft.id == id, next.draft.photoSessions.isEmpty else {
                    throw MappingError.invalid("Дождитесь завершения выбора и получения всех фотографий.")
                }
                _ = try next.draftRecord(now: Date())
                if !operations.isEmpty {
                    guard let files else { throw StorageError.writesBlocked }
                    for operation in operations {
                        if let bytes = retained[operation.id] { try files.stage(bytes.data, for: operation) }
                        try files.promote(operation)
                        _ = try files.read(operation.attachment)
                    }
                }
                _ = try next.save(preparedPhotos: operations)
            }
            success = true
            if let files {
                for operation in operations {
                    do { try await storage.run { try files.complete(operation) } }
                    catch { photoError = "Наблюдение и оригиналы сохранены. Миниатюра/завершение операции требует повтора: \(error.localizedDescription)" }
                }
            }
        } catch {
            self.error = "Наблюдение не сохранено: \(error.localizedDescription) Черновик сохранён в работающем приложении. Повторите «Сохранить наблюдение» без пересъёмки. Незаписанные байты в памяти не переживут завершение приложения."
        }
        await refreshPhotoRecovery()
    }
}
