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
    private func search() { plans = ShoppingPlanner.plans(for: query.split(separator: ",").map(String.init), stores: store.stores, preferences: store.preferences, reviews: store.reviews) }
}

private struct PlanCard: View {
    let plan: ShoppingPlan; let recommended: Bool; let choose: () -> Void
    @EnvironmentObject private var store: AppStore
    @State private var reviewStore: GroceryStore?
    var body: some View { VStack(alignment: .leading, spacing: 12) { HStack { VStack(alignment: .leading) { if recommended { Text("RECOMMENDED FOR YOU").font(.caption.bold()).foregroundStyle(Color.appBlue) }; Text(plan.title).font(.title3.bold()) }; Spacer(); VStack(alignment: .trailing) { Text(plan.estimatedCost, format: .currency(code: "USD")).bold(); Text("~\(plan.travelMinutes) min").font(.caption).foregroundStyle(.secondary) } }; ForEach(plan.stops) { stop in HStack(alignment: .top) { Image(systemName: "storefront").foregroundStyle(Color.appBlue); VStack(alignment: .leading) { Text(stop.store.name).bold(); Text(stop.products.map(\.product).joined(separator: ", ")).font(.subheadline); HStack { Text("\(stop.store.distanceMiles, specifier: "%.1f") mi · \(stop.store.travelMinutes) min"); if let rating = store.averageRating(for: stop.store.name) { Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill").foregroundStyle(.orange) } }.font(.caption).foregroundStyle(.secondary); Button("Reviews") { reviewStore = stop.store }.font(.caption) } } }; ForEach(Array(plan.substitutions.keys.sorted()), id: \.self) { item in Label("Try \(plan.substitutions[item]!) instead of \(item)", systemImage: "arrow.triangle.swap").font(.subheadline).foregroundStyle(.orange) }; HStack(alignment: .top) { VStack(alignment: .leading) { Text("Pros").bold(); ForEach(plan.pros, id: \.self) { Label($0, systemImage: "plus.circle.fill").foregroundStyle(Color.appBlue) } }; Spacer(); VStack(alignment: .leading) { Text("Cons").bold(); ForEach(plan.cons, id: \.self) { Label($0, systemImage: "minus.circle.fill").foregroundStyle(.orange) } } }.font(.caption); Button("Choose this plan", action: choose).buttonStyle(.borderedProminent) }.padding(.vertical, 10).sheet(item: $reviewStore) { ReviewSheet(store: $0) } }
}

private struct ReviewSheet: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    let store: GroceryStore
    @State private var rating = 5
    @State private var comment = ""
    var body: some View {
        NavigationStack {
            List {
                Section("Your review") {
                    HStack { ForEach(1...5, id: \.self) { star in Button { rating = star } label: { Image(systemName: star <= rating ? "star.fill" : "star").foregroundStyle(.orange) }.buttonStyle(.plain) } }
                    TextField("What should other shoppers know?", text: $comment, axis: .vertical)
                    Button("Post review") { appStore.addReview(storeName: store.name, rating: rating, comment: comment); comment = "" }.buttonStyle(.borderedProminent)
                }
                Section("Shop reviews") {
                    if appStore.reviews(for: store.name).isEmpty { Text("No reviews yet. Be the first.").foregroundStyle(.secondary) }
                    ForEach(appStore.reviews(for: store.name)) { review in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(review.username).bold(); Spacer(); Text(String(repeating: "★", count: review.rating)).foregroundStyle(.orange) }
                            if !review.comment.isEmpty { Text(review.comment) }
                            Text(review.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(store.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
