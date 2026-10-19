import SwiftUI
import ImageIO

struct PhotoDetailView: View {
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    let photo: PhotoObservation
    @FocusState private var focused: Bool
    @State private var metadata: PhotoMetadata
    @State private var reason = ""
    @State private var baseline: UUID?
    @State private var initialized = false
    @State private var fullScreen = false
    @State private var failure: String?
    init(photo: PhotoObservation) { self.photo = photo; _metadata = State(initialValue: photo.metadata) }
    private var attachment: PhotoAttachment? { mapping.workflow?.journal.photoAttachments.first { $0.id == photo.attachmentID } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { fullScreen = true } label: { PhotoThumbnail(photo: photo).frame(maxWidth: .infinity) }
                        .accessibilityIdentifier("photoOpenFullScreen")
                    Text("Нажмите для просмотра с увеличением").font(.caption)
                }
                Section("Метаданные фотографии") {
                    TextField("Название", text: $metadata.name).focused($focused).accessibilityIdentifier("photoName")
                    TextField("Номер", text: $metadata.number).focused($focused).accessibilityIdentifier("photoNumber")
                    TextField("Описание", text: $metadata.description, axis: .vertical).focused($focused).accessibilityIdentifier("photoDescription")
                    Picker("Категория", selection: $metadata.category) {
                        Text("Не указана").tag(Optional<PhotoCategory>.none)
                        ForEach(PhotoCategory.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    TextField("Причина исправления", text: $reason).focused($focused).accessibilityIdentifier("photoCorrectionReason")
                    Button("Сохранить метаданные") {
                        do {
                            guard mapping.workflow != nil else { throw StorageError.writesBlocked }
                            try mapping.workflow!.correctPhoto(photo.id, baselineRevisionID: baseline, metadata: metadata, reason: reason)
                            baseline = mapping.workflow?.journal.photoRevisions.last { $0.photoID == photo.id }?.id
                            reason = ""; failure = nil
                        } catch { failure = error.localizedDescription }
                    }.disabled(metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("photoSaveMetadata")
                    if let failure { Text(failure).foregroundStyle(.red) }
                }
                Section("Время и источник") {
                    Text(PhotoDateText.capture(photo)).accessibilityIdentifier("photoCaptureTime")
                    Text("Импорт: \(MeasurementDateText.format(photo.importedAt, detailed: true))")
                    Text(photo.source == .camera ? "Камера" : photo.source == .photos ? "Фото" : "Файлы")
                    Text(photo.capturedAt == nil ? "Момент съёмки не установлен. Дата EXIF без часового пояса сохраняется как исходный текст." :
                        "Дата EXIF с часовым поясом; не проверена независимо.").font(.caption)
                    if let attachment {
                        Text(attachment.representation.contains("encoded to JPEG") ?
                            "Камера предоставила изображение без исходного файла. Сохранена JPEG-копия; часть метаданных может отсутствовать." :
                            photo.source == .photos ? "Сохранены полученные байты. Фото может предоставить преобразованную копию; идентичность оригиналу медиатеки не подтверждена." :
                            "Полученный файл сохранён без изменения байтов.").font(.caption)
                        Text("\(attachment.format) · \(attachment.pixelWidth) × \(attachment.pixelHeight) · \(attachment.byteCount) байт")
                        Text("SHA-256: \(attachment.sha256)").font(.caption).textSelection(.enabled)
                        if let name = attachment.originalFilename { Text("Исходное имя: \(name)") }
                    }
                }
                Section("Исходная привязка") {
                    Text("Точка: \(photo.context.pointID.uuidString)").font(.caption)
                    Text(photo.context.locationBasis == .unknownBeforeFirstSave ? "Место съёмки неизвестно · фото черновика" : "Версия расположения: \(photo.context.pointVersion)")
                    Text(photo.context.pointRevisionID.uuidString).font(.caption)
                    if let point = mapping.workflow?.journal.photoPoint(photo.context) {
                        if photo.context.locationBasis == .pointRevision {
                            Text("Пикет при импорте: \(point.picket)")
                            Text(point.coordinates?.provenance ?? "Координаты неизвестны")
                        } else {
                            Text("Проект, горизонт и выработка зафиксированы до выбора фото. Расположение сохранённой точки не является местом съёмки.").font(.caption)
                        }
                        NavigationLink("Исходная версия точки · расположение точки") {
                            MappingObservationDetail(record: point, historical: true, historicalVersion: photo.context.pointVersion)
                        }
                        NavigationLink("Актуальная карточка точки") { MappingObservationDetail(record: point) }
                    }
                    Text("EXIF/GPS не используется для координат точки.").font(.caption)
                }
                Section("История метаданных") {
                    historyRow(photo.metadata, title: "Версия 1 · импорт", reason: nil)
                    ForEach(mapping.workflow?.journal.photoRevisions.filter { $0.photoID == photo.id } ?? []) { revision in
                        historyRow(revision.metadata, title: "Версия \(revision.version) · \(MappingCorrectionDateText.format(revision.correctedAt))", reason: revision.reason)
                    }
                }
                Section("UUID фотографии / вложения") {
                    Text(photo.id.uuidString); Text(photo.attachmentID.uuidString)
                }.font(.caption).textSelection(.enabled)
            }.navigationTitle("Фотография")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Закрыть") { dismiss() }.accessibilityIdentifier("photoCloseDetail") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focused = false } }
                }
                .onAppear {
                    guard !initialized else { return }; initialized = true
                    metadata = mapping.workflow?.journal.metadata(for: photo) ?? photo.metadata
                    baseline = mapping.workflow?.journal.photoRevisions.last { $0.photoID == photo.id }?.id
                }
                .fullScreenCover(isPresented: $fullScreen) { PhotoFullScreen(photo: photo) }
        }
    }
    private func historyRow(_ values: PhotoMetadata, title: String, reason: String?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption); Text(values.name + (values.number.isEmpty ? "" : " · " + values.number))
            Text(values.description); Text(values.category?.label ?? "Категория не указана")
            if let reason { Text(reason).font(.caption) }
        }
    }
}

private struct PhotoFullScreen: View {
    @EnvironmentObject private var mapping: MappingModel
    @Environment(\.dismiss) private var dismiss
    let photo: PhotoObservation
    @State private var image: UIImage?
    @State private var error: String?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image { ZoomablePhoto(image: image).ignoresSafeArea().accessibilityIdentifier("photoZoomView") }
            else if let error { Text(error).foregroundStyle(.white).padding(40) }
            else { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
            Button("Закрыть") { dismiss() }.padding().background(.regularMaterial, in: Capsule()).padding()
                .accessibilityIdentifier("photoCloseFullScreen")
        }.task {
            guard let files = mapping.photoStore, let attachment = mapping.workflow?.journal.photoAttachments.first(where: { $0.id == photo.attachmentID }) else { return }
            do {
                // Bounded display derivative; full received original remains untouched on disk.
                let data = try await Task.detached { () throws -> Data in
                    let bytes = try files.read(attachment)
                    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096] as CFDictionary),
                          let data = UIImage(cgImage: cg).pngData() else { throw StorageError.invalidRecord }
                    return data
                }.value
                image = UIImage(data: data)
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView(); scroll.accessibilityIdentifier = "photoZoomView"; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 8
        scroll.delegate = context.coordinator
        let view = UIImageView(image: image); view.contentMode = .scaleAspectFit
        view.isAccessibilityElement = true; view.accessibilityLabel = "Фотография, увеличение жестом"
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.frame = scroll.bounds
        scroll.addSubview(view); context.coordinator.imageView = view
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        if scroll.zoomScale == 1 { context.coordinator.imageView?.frame = scroll.bounds }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}
