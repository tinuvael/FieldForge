import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO

struct DraftPhotosSection: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var session: DraftPhotoSession?
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var loading = false
    @State private var viewing: PhotoImportOperation?
    @State private var active = false
    private var photos: [PhotoImportOperation] { mapping.workflow?.draft.photos ?? [] }
    private var busy: Bool { loading || mapping.photoBusy }
    var body: some View {
        let frozenSession = session
        Section("Фотографии: \(photos.count)") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Камера", systemImage: "camera") { startCamera() }.accessibilityIdentifier("draftPhotoCamera")
                    Spacer()
                    Button("Фото", systemImage: "photo.on.rectangle") { if freeze() { showLibrary = true } }.accessibilityIdentifier("draftPhotoLibrary")
                    Spacer()
                    Button("Файлы", systemImage: "folder") { if freeze() { showFiles = true } }.accessibilityIdentifier("draftPhotoFiles")
                }.disabled(busy)
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.environment["P41_PHOTOS"] != nil {
                    Button("Добавить тестовые фото в черновик") {
                        guard freeze(), let frozen = session else { return }
                        loading = true
                        Task {
                            await mapping.importDraftPhotoTestFixtures(session: frozen)
                            mapping.endDraftPhotos(frozen); loading = false
                        }
                    }.disabled(busy).accessibilityIdentifier("draftPhotoImportFixtures")
                }
                #endif
                if loading { ProgressView("Получение фотографий… Дождитесь завершения перед сохранением.") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
                    ForEach(photos) { operation in
                        VStack {
                            Button { viewing = operation } label: {
                                VStack {
                                    DraftPhotoImage(operation: operation)
                                    Text(operation.photo.metadata.name).lineLimit(2)
                                    Text(mapping.retainedPhotos[operation.id] != nil ?
                                        "Байты в памяти · оригинал на диске ещё не подтверждён" :
                                        "Оригинал проверен на диске · точка ещё не сохранена")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("draftPhoto-\(operation.id.uuidString)")
                            Button("Убрать из черновика", role: .destructive) {
                                mapping.removeDraftPhoto(operation.id, draftID: operation.photo.context.pointID)
                            }.disabled(busy).font(.caption)
                        }
                    }
                }
                if !photos.isEmpty {
                    DisclosureGroup("О фотографиях черновика") {
                        Text("До успешного сохранения наблюдения фото принадлежат черновику. Незаписанные снимки в памяти потеряются при завершении приложения. Место съёмки неизвестно; XY точки и EXIF/GPS его не заменяют.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !mapping.pendingPhotos.filter({ $0.photo.context.locationBasis == .unknownBeforeFirstSave &&
                    mapping.workflow?.journal.photos.contains($0.photo) != true && !photos.contains($0) }).isEmpty {
                    Text("Есть файлы незавершённых или удалённых черновиков. Они сохранены для проверенного восстановления. Форма после перезапуска не восстанавливается; файлы не назначаются новой точке.").font(.caption).foregroundStyle(.orange)
                }
                if let error = mapping.photoRecoveryError { Text(error).font(.caption).foregroundStyle(.red) }
            }.buttonStyle(.borderless)
                .onAppear { active = true }
                .onDisappear { active = false }
                .alert("Фотографии", isPresented: Binding(get: { active && mapping.photoError != nil }, set: { if !$0 && active { mapping.photoError = nil } })) {
                    Button("Понятно", role: .cancel) { mapping.photoError = nil }
                } message: { Text(mapping.photoError ?? "") }
                .sheet(isPresented: $showLibrary, onDismiss: finishDismissal) {
                    PhotoLibraryPicker { results in
                        guard let frozen = frozenSession else { showLibrary = false; return }
                        loading = true; showLibrary = false
                        Task {
                            defer { mapping.endDraftPhotos(frozen); loading = false }
                            for result in results {
                                do { await mapping.receiveDraftPhoto(try await PhotoLibraryPicker.load(result), session: frozen) }
                                catch { mapping.photoError = "Не удалось получить фото: \(error.localizedDescription)" }
                            }
                        }
                    }.ignoresSafeArea()
                }
                .fullScreenCover(isPresented: $showCamera, onDismiss: finishDismissal) {
                    PhotoCameraPicker { result in
                        guard let frozen = frozenSession else { showCamera = false; return }
                        loading = true; showCamera = false
                        Task {
                            defer { mapping.endDraftPhotos(frozen); loading = false }
                            switch result {
                            case .success(let received): if let received { await mapping.receiveDraftPhoto(received, session: frozen) }
                            case .failure(let error): mapping.photoError = error.localizedDescription
                            }
                        }
                    }.ignoresSafeArea()
                }
                .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: true, onCompletion: { result in
                    guard let frozen = frozenSession else { return }
                    loading = true
                    Task {
                        defer { mapping.endDraftPhotos(frozen); loading = false }
                        switch result {
                        case .success(let urls):
                            for url in urls {
                                do { await mapping.receiveDraftPhoto(try await PhotoFilesLoader.load(url), session: frozen) }
                                catch { mapping.photoError = "Не удалось прочитать файл: \(error.localizedDescription)" }
                            }
                        case .failure(let error):
                            if (error as NSError).code != NSUserCancelledError { mapping.photoError = error.localizedDescription }
                        }
                    }
                }, onCancellation: { if let frozenSession { mapping.endDraftPhotos(frozenSession) } })
                .sheet(item: $viewing) { operation in
                    NavigationStack {
                        ScrollView {
                            DraftPhotoImage(operation: operation, maximumPixels: 4096).padding()
                            Text(PhotoDateText.capture(operation.photo))
                            Text("Место съёмки неизвестно").font(.caption)
                        }.navigationTitle("Фото черновика")
                            .toolbar { Button("Закрыть") { viewing = nil }.accessibilityIdentifier("draftPhotoClosePreview") }
                    }
                }
        }
    }
    private func freeze() -> Bool {
        do { session = try mapping.beginDraftPhotos(); return true }
        catch { mapping.photoError = error.localizedDescription; return false }
    }
    private func finishDismissal() {
        if !loading, let session { mapping.endDraftPhotos(session) }
    }
    private func startCamera() {
        guard freeze(), let frozen = session else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            mapping.endDraftPhotos(frozen)
            mapping.photoError = "Камера недоступна на этом устройстве (в Simulator камеры нет). Используйте Фото или Файлы."
            return
        }
        loading = true
        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            var allowed = status == .authorized
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            loading = false
            if allowed, mapping.workflow?.draft.photoSessions.contains(frozen.id) == true { showCamera = true }
            else { mapping.endDraftPhotos(frozen); mapping.photoError = "Доступ к камере запрещён или черновик закрыт. Используйте Фото / Файлы." }
        }
    }
}

private struct DraftPhotoImage: View {
    @EnvironmentObject private var mapping: MappingModel
    let operation: PhotoImportOperation
    var maximumPixels = 400
    @State private var image: UIImage?
    @State private var error: String?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if let error { Text(error).font(.caption) }
            else { ProgressView() }
        }.frame(maxHeight: maximumPixels == 400 ? 110 : 1000)
            .task(id: operation.id) {
                do {
                    let bytes = try await mapping.draftPhotoData(operation)
                    let limit = maximumPixels
                    let cg = try await Task.detached { () throws -> CGImage in
                        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: limit] as CFDictionary) else { throw StorageError.invalidRecord }
                        return cg
                    }.value
                    image = UIImage(cgImage: cg)
                } catch { self.error = error.localizedDescription }
            }
    }
}
