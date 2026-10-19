#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Isolated UI-test transport; real import/storage path below receives deterministic test bytes.
/// Disabled in Release and on physical devices, like the existing DXF UI fixtures.
extension MappingModel {
    func importPhotoTestFixtures(context: PhotoContext) async {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              let json = ProcessInfo.processInfo.environment["P41_PHOTOS"],
              let values = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return }
        for value in values {
            guard let data = Data(base64Encoded: value) else { continue }
            await importPhoto(ReceivedPhoto(data: data, filename: "same.png", source: .files,
                representation: "UI fixture received bytes"), context: context)
        }
    }
}
#endif
