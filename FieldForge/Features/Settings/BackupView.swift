import SwiftUI
import UIKit

struct BackupView: View {
    @EnvironmentObject private var mapping: MappingModel
    @EnvironmentObject private var measurements: AppModel
    @State private var result: VerifiedBackup?
    @State private var phase: String?
    @State private var error: String?
    @State private var sharing = false
    @State private var worker: Task<Void, Never>?
    @State private var cancellation: BackupCancellation?

    var body: some View {
        Form {
            Section {
                Text("Все проекты, исходные наблюдения, история исправлений, оригиналы фотографий и DXF, независимый журнал измерений и файлы восстановления.")
                Text("Оригинальные фотографии могут содержать EXIF и сведения о местоположении. Храните архив в защищённом месте.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Несохранённые черновики не входят в резервную копию. Сохраните их перед созданием архива.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink("Восстановить из резервной копии", destination: RestoreView())
                    .disabled(phase != nil)
            }
            Section("Резервная копия") {
                if let manifest = result?.manifest {
                    counts(manifest)
                } else if let journal = mapping.workflow?.journal {
                    LabeledContent("Проекты", value: "\(journal.projects.count)")
                    LabeledContent("Наблюдения", value: "\(journal.observations.count)")
                    LabeledContent("Фотографии", value: "\(journal.photos.count)")
                    LabeledContent("Планы DXF", value: "\(journal.plans.count)")
                }
                if let result {
                    LabeledContent("Размер архива", value: ByteCountFormatter.string(fromByteCount: Int64(result.byteCount), countStyle: .file))
                    Label(result.report.complete ? "Резервная копия проверена" : "Не удалось создать полную резервную копию",
                          systemImage: result.report.complete ? "checkmark.shield" : "exclamationmark.triangle")
                        .foregroundStyle(result.report.complete ? Color.green : Color.orange)
                    if !result.report.complete {
                        Text("Неполный архив сохраняет доступные файлы и отчёт. Он не заменяет полную резервную копию.").font(.footnote)
                        ForEach(Array(result.report.problems.enumerated()), id: \.offset) { _, problem in
                            VStack(alignment: .leading) {
                                Text(problem.reason)
                                Text(problem.path).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                    Button(result.report.complete ? "Сохранить в Файлы" : "Сохранить неполный архив и отчёт") { sharing = true }
                        .disabled(phase != nil)
                }
                if let phase {
                    ProgressView(phase)
                    Button("Отменить", role: .cancel) { cancellation?.cancel(); worker?.cancel() }
                } else {
                    Button("Создать резервную копию", action: start)
                        .disabled(mapping.loading || mapping.workflow == nil || measurements.backupInProgress)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Резервное копирование")
        .sheet(isPresented: $sharing) { if let result { BackupShareSheet(files: result.files) } }
        .onDisappear {
            if !sharing { cancellation?.cancel(); worker?.cancel(); result?.files.cleanup(); result = nil }
        }
    }
    private func counts(_ manifest: BackupManifest) -> some View {
        Group {
            LabeledContent("Проекты", value: "\(manifest.projectCount)")
            LabeledContent("Наблюдения", value: "\(manifest.observationCount)")
            LabeledContent("Фотографии", value: "\(manifest.attachments.filter { $0.kind == "photo" }.count)")
            LabeledContent("Планы DXF", value: "\(manifest.attachments.filter { $0.kind == "dxf" }.count)")
            LabeledContent("Независимые измерения", value: "\(manifest.measurementIDs.count)")
        }
    }
    private func start() {
        result?.files.cleanup(); result = nil; error = nil
        let token = BackupCancellation(); cancellation = token; phase = "Подготовка архива…"
        worker = Task { @MainActor in
            defer { phase = nil; cancellation = nil; worker = nil }
            do {
                let source = try measurements.beginBackup()
                defer { measurements.endBackup() }
                guard let photos = mapping.photoStore, let plans = mapping.planStore else { throw StorageError.writesBlocked }
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                let staged = try await withTaskCancellationHandler {
                    try await mapping.storage.captureBackup(measurements: source, photos: photos.root, plans: plans.root,
                                                            cancellation: token, applicationVersion: version)
                } onCancel: { token.cancel() }
                let completed = try await withTaskCancellationHandler {
                    try await Task.detached(priority: .userInitiated) {
                        try OfflineBackup.package(staged, cancellation: token, verifying: {
                            Task { @MainActor in
                                if cancellation === token { phase = "Проверка целостности…" }
                            }
                        })
                    }.value
                } onCancel: { token.cancel() }
                if Task.isCancelled { completed.files.cleanup(); throw CancellationError() }
                result = completed
            } catch is CancellationError { error = "Создание резервной копии отменено. Исходные данные сохранены." }
            catch { self.error = "Не удалось создать полную резервную копию: \(error.localizedDescription)" }
        }
    }
}
private struct BackupShareSheet: UIViewControllerRepresentable {
    // Strong ownership preserves ZIP until native sharing finishes/dismisses.
    let files: MappingExportFiles
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: files.urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
