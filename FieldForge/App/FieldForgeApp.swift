import SwiftUI

@main struct FieldForgeApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var mapping = MappingModel()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model).environmentObject(mapping).environment(\.locale, Locale(identifier: "ru_RU")) }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            MappingView().tabItem { Label("Картирование", systemImage: "square.and.pencil") }.tag(0)
            NavigationStack { HorizonPlansView() }
                .tabItem { Label("План", systemImage: "map") }.tag(1)
            WedgesView()
                .tabItem { Label("Клинья", systemImage: "triangle") }.tag(2)
        }
        .tint(Color("AccentColor"))
        .onAppear { updateLifecycle() }
        .onChange(of: selectedTab) { _, _ in updateLifecycle() }
        .onChange(of: scenePhase) { _, _ in updateLifecycle() }
        .alert("FieldForge", isPresented: Binding(get: { model.errorMessage != nil },
                                                  set: { if !$0 { model.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private func updateLifecycle() {
        model.setLifecycle(measurementVisible: model.measurementScreenVisible && selectedTab == 0, foreground: scenePhase == .active)
    }
}
