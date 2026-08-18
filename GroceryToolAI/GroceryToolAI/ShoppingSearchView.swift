import SwiftUI

struct ShoppingSearchView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = "Coca-Cola, milk"
    @State private var plans: [ShoppingPlan] = []
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack { TextField("What do you want to buy? Separate items with commas", text: $query).textFieldStyle(.roundedBorder).onSubmit(search); Button("Compare stores", action: search).buttonStyle(.borderedProminent).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty) }.padding(.horizontal)
                if plans.isEmpty { ContentUnavailableView("Plan your grocery trip", systemImage: "car.side", description: Text("Compare one-stop and multi-store options, including similar nearby products.")) }
                else { List { ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in PlanCard(plan: plan, recommended: index == 0) { store.select(plan) } } }.listStyle(.inset) }
            }.padding(.top).navigationTitle("Smart store search").onAppear { if plans.isEmpty { search() } }
        }
    }
    private func search() { plans = ShoppingPlanner.plans(for: query.split(separator: ",").map(String.init), stores: store.stores, preferences: store.preferences) }
}

private struct PlanCard: View {
    let plan: ShoppingPlan; let recommended: Bool; let choose: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 12) { HStack { VStack(alignment: .leading) { if recommended { Text("RECOMMENDED FOR YOU").font(.caption.bold()).foregroundStyle(.green) }; Text(plan.title).font(.title3.bold()) }; Spacer(); VStack(alignment: .trailing) { Text(plan.estimatedCost, format: .currency(code: "USD")).bold(); Text("~\(plan.travelMinutes) min").font(.caption).foregroundStyle(.secondary) } }; ForEach(plan.stops) { stop in HStack(alignment: .top) { Image(systemName: "storefront").foregroundStyle(.green); VStack(alignment: .leading) { Text(stop.store.name).bold(); Text(stop.products.map(\.product).joined(separator: ", ")).font(.subheadline); Text("\(stop.store.distanceMiles, specifier: "%.1f") mi · \(stop.store.travelMinutes) min").font(.caption).foregroundStyle(.secondary) } } }; ForEach(Array(plan.substitutions.keys.sorted()), id: \.self) { item in Label("Try \(plan.substitutions[item]!) instead of \(item)", systemImage: "arrow.triangle.swap").font(.subheadline).foregroundStyle(.orange) }; HStack(alignment: .top) { VStack(alignment: .leading) { Text("Pros").bold(); ForEach(plan.pros, id: \.self) { Label($0, systemImage: "plus.circle.fill").foregroundStyle(.green) } }; Spacer(); VStack(alignment: .leading) { Text("Cons").bold(); ForEach(plan.cons, id: \.self) { Label($0, systemImage: "minus.circle.fill").foregroundStyle(.orange) } } }.font(.caption); Button("Choose this plan", action: choose).buttonStyle(.bordered) }.padding(.vertical, 10) }
}
