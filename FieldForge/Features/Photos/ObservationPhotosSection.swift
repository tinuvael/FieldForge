import SwiftUI
import PhotosUI
import AVFoundation

struct ObservationPhotosSection: View {
    @EnvironmentObject private var mapping: MappingModel
    let pointID: UUID
    @State private var context: PhotoContext?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var replacement: PhotoImportOperation?
    @State private var selection: PhotoObservation?
    @State private var loading = false
    private var photos: [PhotoObservation] { mapping.workflow?.journal.photos.filter { $0.context.pointID == pointID } ?? [] }
    private var busy: Bool { loading || mapping.photoBusy }
    var body: some View {
        Section("Фотографии: \(photos.count)") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Камера", systemImage: "camera") { startCamera() }.accessibilityIdentifier("photoCamera")
                    Spacer()
                    Button("Фото", systemImage: "photo.on.rectangle") { freeze(); showLibrary = context != nil }.accessibilityIdentifier("photoLibrary")
                    Spacer()
                    Button("Файлы", systemImage: "folder") { freeze(); replacement = nil; showFiles = context != nil }.accessibilityIdentifier("photoFiles")
                }.buttonStyle(.borderless).disabled(busy)
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.environment["P41_PHOTOS"] != nil {
                    Button("Добавить тестовые фото") {
                        freeze()
                        if let frozen = context {
                            loading = true
                            Task { await mapping.importPhotoTestFixtures(context: frozen); loading = false }
                        }
                    }.disabled(busy).accessibilityIdentifier("photoImportFixtures")
                }
                #endif
                if busy { ProgressView("Сохранение фотографий…") }
                if photos.isEmpty { Text("Добавьте фотографии к сохранённой точке. План и координаты не требуются.").font(.caption) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
                    ForEach(photos) { photo in
                        Button { selection = photo } label: {
                            VStack(alignment: .leading) {
                                PhotoThumbnail(photo: photo)
                                Text(mapping.workflow?.journal.metadata(for: photo).name ?? photo.metadata.name).lineLimit(2)
                                Text(PhotoDateText.capture(photo)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("photo-\(photo.id.uuidString)")
                    }
                }
                ForEach(mapping.pendingPhotos.filter { $0.photo.context.pointID == pointID }) { operation in
                    VStack(alignment: .leading) {
                        Text("Незавершённая операция: \(operation.photo.metadata.name)").font(.caption)
                        Button("Повторить сохранение") { Task { await mapping.retryPhoto(operation) } }.disabled(busy)
                        Button("Выбрать тот же файл для восстановления") { replacement = operation; showFiles = true }.disabled(busy)
                    }
                }
                if let error = mapping.photoRecoveryError { Text(error).foregroundStyle(.red) }
                Text("Привязка фиксируется до выбора изображения. EXIF/GPS не задаёт координаты точки.").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .task { mapping.refreshPhotoRecovery() }
            .alert("Фотографии", isPresented: Binding(get: { mapping.photoError != nil }, set: { if !$0 { mapping.photoError = nil } })) {
                Button("Понятно", role: .cancel) { mapping.photoError = nil }
            } message: { Text(mapping.photoError ?? "") }
            .sheet(isPresented: $showLibrary) {
                PhotoLibraryPicker { results in
                    showLibrary = false
                    guard let frozen = context, !results.isEmpty else { return }
                    loading = true
                    Task {
                        defer { loading = false }
                        for result in results {
                            do { let received = try await PhotoLibraryPicker.load(result); await mapping.importPhoto(received, context: frozen) }
                            catch { mapping.photoError = "Не удалось получить фото: \(error.localizedDescription)" }
                        }
                    }
                }.ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCamera) {
                PhotoCameraPicker { result in
                    showCamera = false
                    switch result {
                    case .success(let photo):
                        if let photo, let frozen = context { Task { await mapping.importPhoto(photo, context: frozen) } }
                    case .failure(let error): mapping.photoError = error.localizedDescription
                    }
                }.ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: replacement == nil) { result in
                let frozen = context; let recovery = replacement
                switch result {
                case .success(let urls):
                    loading = true
                    Task {
                        defer { loading = false }
                        for url in urls {
                            do {
                                let received = try await Task.detached(priority: .userInitiated) {
                                    let access = url.startAccessingSecurityScopedResource()
                                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                                    // Coordinate File Provider downloads/read access, then copy before scope closes.
                                    var readError: Error?; var data: Data?; var coordinatorError: NSError?
                                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readable in
                                        do {
                                            guard let size = try readable.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                                                  size <= ManagedPhotoStore.maximumBytes else { throw StorageError.invalidRecord }
                                            data = try Data(contentsOf: readable)
                                        } catch { readError = error }
                                    }
                                    if let error = coordinatorError ?? readError as NSError? { throw error }
                                    guard let data else { throw StorageError.invalidRecord }
                                    return ReceivedPhoto(data: data, filename: url.lastPathComponent, source: .files,
                                        representation: "Files supplied file; received bytes preserved; upstream transformations unknown")
                                }.value
                                if let recovery { await mapping.retryPhoto(recovery, replacement: received.data) }
                                else if let frozen { await mapping.importPhoto(received, context: frozen) }
                            } catch { mapping.photoError = "Не удалось прочитать файл: \(error.localizedDescription)" }
                        }
                    }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { mapping.photoError = "Доступ к файлу не получен: \(error.localizedDescription)" }
                }
            }
            .sheet(item: $selection) { PhotoDetailView(photo: $0) }
        }
    }
    private func freeze() {
        do { context = try mapping.workflow?.journal.photoContext(for: pointID) }
        catch { context = nil; mapping.photoError = error.localizedDescription }
    }
    private func startCamera() {
        freeze()
        guard context != nil else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            mapping.photoError = "Камера недоступна на этом устройстве (в Simulator камеры нет). Используйте Фото или Файлы."
            return
        }
        loading = true
        Task {
            defer { loading = false }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            var allowed = status == .authorized
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            if allowed { showCamera = true }
            else { mapping.photoError = "Доступ к камере запрещён. Разрешите его в настройках iOS или используйте Фото / Файлы." }
        }
    }
}

struct PhotoThumbnail: View {
    @EnvironmentObject private var mapping: MappingModel
    let photo: PhotoObservation
    @State private var image: UIImage?
    @State private var failure: String?
    @State private var attempt = 0
    var body: some View {
        VStack {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(height: 110) }
            else if let failure {
                Image(systemName: "exclamationmark.triangle")
                Text(failure).font(.caption2)
                Button("Повторить просмотр") { attempt += 1 }.font(.caption)
            } else { ProgressView().frame(height: 110) }
        }.task(id: attempt) {
            guard let files = mapping.photoStore,
                  let attachment = mapping.workflow?.journal.photoAttachments.first(where: { $0.id == photo.attachmentID }) else { return }
            do {
                let data = try await Task.detached { try files.thumbnail(attachment) }.value
                image = UIImage(data: data); failure = nil
            } catch { image = nil; failure = error.localizedDescription }
        }
    }
}

enum PhotoDateText {
    static func capture(_ photo: PhotoObservation) -> String {
        photo.capturedAt.map { "Съёмка: " + MeasurementDateText.format($0, detailed: true) } ??
            photo.captureTimeText.map { "Съёмка (EXIF): " + $0.replacingOccurrences(of: "offset unknown", with: "часовой пояс неизвестен") } ?? "Время съёмки неизвестно"
    }
}
