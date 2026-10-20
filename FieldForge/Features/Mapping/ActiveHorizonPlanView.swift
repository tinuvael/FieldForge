import SwiftUI

/// Display selection never changes source-plan relationships or draft coordinates.
struct ActiveHorizonPlanView: View {
    @EnvironmentObject private var mapping: MappingModel
    @State private var managing = false
    private var horizon: MappingHorizon? { mapping.workflow?.selectedHorizon }
    var body: some View {
        Group {
            if let horizon {
                VStack(spacing: 0) {
                    if let plan = mapping.activePlan(for: horizon.id) {
                        VStack(spacing: 2) {
                            Text(horizon.displayName).font(.headline)
                            Text("Версия \(plan.version) · \(mapping.hasExplicitPlan(for: horizon.id) ? "выбрана для просмотра" : "последний импорт по умолчанию")")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(8)
                        HorizonPlanLoader(plan: plan, selecting: false, onSelection: nil).id(plan.id)
                    } else {
                        ContentUnavailableView {
                            Label("Нет плана · \(horizon.displayName)", systemImage: "map")
                        } actions: {
                            Button("Загрузить DXF") { managing = true }.buttonStyle(.borderedProminent)
                        }
                    }
                }.id(horizon.id)
            } else {
                ContentUnavailableView("Выберите горизонт", systemImage: "map", description: Text("Укажите проект и горизонт во вкладке «Картирование»."))
            }
        }
        .navigationTitle("План").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if horizon != nil {
                Button("Планы и версии", systemImage: "square.stack") { managing = true }
            }
        }
        .sheet(isPresented: $managing) {
            NavigationStack {
                HorizonPlansView().id(horizon?.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { managing = false } } }
            }
        }
        .onChange(of: horizon?.id) { _, _ in managing = false }
    }
}
