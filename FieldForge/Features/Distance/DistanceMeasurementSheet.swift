import AVFoundation
import SwiftUI
import ARKit

@MainActor final class DistanceCameraModel: ObservableObject {
    private var adapter: ARDistanceSession?
    private var controller: DistanceMeasurementController?
    private var timer: Timer?
    private var visible = false
    private var foreground = false
    private var generation = 0
    private var unavailable: DistanceStatus = .starting
    var camera: ARSCNView? { adapter?.view }
    var status: DistanceStatus { controller?.status ?? unavailable }
    var first: DistancePoint? { controller?.first }
    var second: DistancePoint? { controller?.second }
    var metres: Double? { controller?.metres }
    var canSelect: Bool { controller?.canSelect == true }
    var needsRetake: Bool { controller?.needsRetake == true }
    var source: String? { (second ?? first ?? controller?.candidate)?.source.label }

    func open(active: Bool) { visible = true; setActive(active) }
    func setActive(_ active: Bool) {
        foreground = active
        if active && visible { activate() }
        else { stop(.background) }
    }
    func close() { visible = false; stop(.closed) }
    func finishResult() -> DistanceResult? {
        controller?.refresh()
        return controller?.result
    }
    func retake() {
        guard visible && foreground else { return }
        stop(.closed); activate()
    }
    func select() {
        controller?.select()
        render()
        objectWillChange.send()
    }
    private func activate() {
        guard controller?.running != true else { return }
        generation += 1
        let request = generation
        guard ARDistanceSession.supported else { unavailable = .unsupported; objectWillChange.send(); return }
        Task { @MainActor [weak self] in
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
            guard let self, self.visible, self.foreground, request == self.generation else { return }
            guard granted else { self.stop(.cameraDenied); return }
            if self.adapter == nil {
                let adapter = ARDistanceSession()
                adapter.onInterruption = { [weak self] in self?.stop(.interrupted) }
                adapter.onInterruptionEnded = { [weak self] in
                    guard let self, self.visible, self.foreground else { return }
                    self.activate()
                }
                adapter.onTrackingLoss = { [weak self] reason in
                    self?.controller?.trackingLost(reason)
                    self?.render()
                    self?.objectWillChange.send()
                }
                adapter.onFailure = { [weak self] in self?.stop(.failed) }
                self.adapter = adapter
                self.controller = DistanceMeasurementController(session: adapter)
            }
            self.controller?.start()
            self.timer?.invalidate()
            let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.poll() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            self.objectWillChange.send()
        }
    }
    private func stop(_ reason: DistanceStatus) {
        generation += 1
        timer?.invalidate(); timer = nil
        controller?.stop(reason)
        unavailable = reason
        render()
        objectWillChange.send()
    }
    private func poll() {
        guard visible && foreground else { return }
        controller?.refresh()
        render()
        objectWillChange.send()
    }
    private func render() { adapter?.render(first: first, second: second) }
    deinit { timer?.invalidate() }
}

struct DistanceMeasurementSheet: View {
    var closeReturnsResult = true
    let onFinish: (DistanceResult?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = DistanceCameraModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let camera = model.camera {
                    DistanceCameraPreview(view: camera)
                }
                Image(systemName: "plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(model.canSelect ? .cyan : .white)
                    .shadow(color: .black, radius: 2)
                    .accessibilityHidden(true)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.ignoresSafeArea()
        .overlay(alignment: .top) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Замерить расстояние").font(.headline)
                    Text(model.metres != nil ? "Две точки выбраны" : (model.first == nil ? "Выбор точки 1" : "Выбор точки 2"))
                        .font(.subheadline)
                }
                Spacer()
                Button("Закрыть", systemImage: "xmark") { finish(acceptResult: closeReturnsResult) }
                    .labelStyle(.iconOnly).frame(minWidth: 52, minHeight: 52)
                    .accessibilityIdentifier("distanceClose")
            }.padding().background(.ultraThinMaterial)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                VStack {
                    Spacer(minLength: 0)
                    controls.frame(height: min(340, geometry.size.height * 0.42))
                        .background(.ultraThinMaterial)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.open(active: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
        .onDisappear { model.close() }
    }
    private var controls: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let metres = model.metres {
                    Text(DistanceMath.text(metres)).font(.system(size: 48, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1).monospacedDigit()
                        .accessibilityIdentifier("distanceResult")
                }
                Label(model.needsRetake ? model.status.message + " Нажмите «Повторить»." : model.status.message,
                      systemImage: model.canSelect || model.metres != nil ? "scope" : "exclamationmark.triangle")
                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("distanceStatus")
                if let source = model.source { Text(source).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                Text("Приблизительный полевой замер. Не геодезический прибор. Точность не проверена; три знака не означают миллиметровую точность.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.metres == nil {
                    Button { model.select() } label: {
                        Text(model.first == nil ? "Точка 1" : "Точка 2")
                            .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
                    }.buttonStyle(.borderedProminent).tint(.cyan).disabled(!model.canSelect)
                        .accessibilityIdentifier("distanceSelectPoint")
                }
                HStack(spacing: 12) {
                    Button("Повторить") { model.retake() }
                        .accessibilityIdentifier("distanceRetake")
                    Button("Готово") { finish() }
                        .accessibilityIdentifier("distanceDone")
                }.buttonStyle(.bordered).controlSize(.large)
            }.padding().frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("distanceControls")
    }
    private func finish(acceptResult: Bool = true) {
        let result = acceptResult ? model.finishResult() : nil
        model.close()
        onFinish(result)
        dismiss()
    }
}

private struct DistanceCameraPreview: UIViewRepresentable {
    let view: ARSCNView
    func makeUIView(context: Context) -> ARSCNView { view }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
        uiView.session.pause()
        uiView.isPlaying = false
    }
}
