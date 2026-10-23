import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import ImageIO

/// Uses provider data rather than UIImage re-encoding. .current reduces transcoding but
/// cannot prove identity with the library's original; that limitation is persisted.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let receive: ([PHPickerResult]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(receive: receive) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let receive: ([PHPickerResult]) -> Void
        init(receive: @escaping ([PHPickerResult]) -> Void) { self.receive = receive }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { receive(results) }
    }
    static func load(_ result: PHPickerResult) async throws -> ReceivedPhoto {
        let provider = result.itemProvider
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { throw StorageError.invalidRecord }
        let filename = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw StorageError.invalidRecord }
                    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                          size <= ManagedPhotoStore.maximumBytes else { throw StorageError.invalidRecord }
                    // Provider URL is temporary and must be read before this callback returns.
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: ReceivedPhoto(data: data, filename: filename,
                        source: .photos, representation: "Photos current representation requested; provider may transform; library original identity unverified"))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct PhotoCameraPicker: UIViewControllerRepresentable {
    @EnvironmentObject private var mapping: MappingModel
    let receive: (Result<ReceivedPhoto?, Error>) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.mediaTypes = [UTType.image.identifier]
        picker.allowsEditing = false; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(storage: mapping.storage, receive: receive) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let receive: (Result<ReceivedPhoto?, Error>) -> Void
        let storage: MappingStorageOwner
        init(storage: MappingStorageOwner, receive: @escaping (Result<ReceivedPhoto?, Error>) -> Void) {
            self.storage = storage; self.receive = receive
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { receive(.success(nil)) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let url = info[.imageURL] as? URL, image = info[.originalImage] as? UIImage
            let metadata = info[.mediaMetadata] as? [String: Any]
            let exif = metadata?[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let wallTime = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
            let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal as String] as? String
            let subseconds = exif?[kCGImagePropertyExifSubsecTimeOriginal as String] as? String
            Task { @MainActor in
                do {
                    let received = try await storage.run { () throws -> ReceivedPhoto in
                        let data: Data, representation: String
                        if let url {
                            data = try Data(contentsOf: url); representation = "camera supplied file; received bytes preserved"
                        } else if let image, let encoded = image.jpegData(compressionQuality: 1) {
                            data = encoded; representation = "camera UIImage encoded to JPEG by app; original encoded bytes unavailable; metadata may be absent"
                        } else { throw StorageError.invalidRecord }
                        return ReceivedPhoto(data: data, filename: nil, source: .camera, representation: representation,
                            captureWallTime: wallTime, captureUTCOffset: offset, captureSubseconds: subseconds)
                    }
                    receive(.success(received))
                } catch { receive(.failure(error)) }
            }
        }
    }
}

/// Shared Files adapter: copy coordinated provider bytes before releasing security scope.
enum PhotoFilesLoader {
    static func load(_ url: URL) async throws -> ReceivedPhoto {
        try await Task.detached(priority: .userInitiated) {
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
    }
}
