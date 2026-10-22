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
                        Picker("Ревизия", selection: Binding(get: { plan.id }, set: { id in
                            if let selected = mapping.plans(for: horizon.id).first(where: { $0.id == id }) { mapping.selectActivePlan(selected) }
                        })) {
                            ForEach(mapping.plans(for: horizon.id)) { item in Text("Ревизия \(item.version)").tag(item.id) }
                        }.pickerStyle(.menu).padding(.horizontal)
                        if mapping.hasUnavailablePlanSelection(for: horizon.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Прежний выбор недоступен. Выберите ревизию.", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                                Button("Выбрать ревизию") { managing = true }.frame(minHeight: 44)
                            }.padding(.horizontal).accessibilityIdentifier("planSelectionFallback")
                        }
                        HorizonPlanLoader(plan: plan, selecting: false, onSelection: nil).id(plan.id)
                    } else {
                        ContentUnavailableView {
                            Label("Нет плана · \(horizon.displayName)", systemImage: "map")
                        } actions: {
                            if mapping.hasUnavailablePlanSelection(for: horizon.id) {
                                Text("Прежний выбор недоступен; на этом горизонте нет планов.").font(.caption)
                            }
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
