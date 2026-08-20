import SwiftUI

struct ShoppingSearchView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationService
    @State private var query = "Coca-Cola, milk"
    @State private var plans: [ShoppingPlan] = []
    @State private var catalogStore: GroceryStore?
    @State private var isLoading = false
    @State private var errorMessage: String?
    private var budgetStatus: GroceryBudgetStatus? {
        GroceryBudgetService.status(for: store.preferences.groceryBudget, receipts: store.receipts)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("What do you want to buy? Separate items with commas", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await search() } }
                    Button("Compare stores") { Task { await search() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .padding(.horizontal)

                if let budgetStatus {
                    HStack(spacing: 10) {
                        Image(systemName: budgetStatus.remaining >= 0 ? "wallet.bifold.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(budgetStatus.remaining >= 0 ? Color.appBlue : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Grocery budget").font(.subheadline.bold())
                            Text(budgetStatus.remaining >= 0
                                 ? "\(budgetStatus.remaining.formatted(.currency(code: "USD"))) remaining this period"
                                 : "\(abs(budgetStatus.remaining).formatted(.currency(code: "USD"))) over budget this period")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(min(max(budgetStatus.progress, 0), 9.99) * 100))%")
                            .font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit()
                    }
                    .padding(12)
                    .background(Color.appBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                }

                if isLoading {
                    ProgressView("Loading real nearby shops and product prices…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                if plans.isEmpty && store.stores.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label("Find real grocery stores", systemImage: "location.magnifyingglass")
                    } description: {
                        Text("Allow location access, then load nearby shops with product prices.")
                    } actions: {
                        Button("Load nearby stores") { Task { await refreshStores() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if !plans.isEmpty {
                            Section("Recommended plans") {
                                ForEach(plans) { plan in
                                    planCard(plan)
                                }
                            }
                        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                            Section {
                                ContentUnavailableView(
                                    "No recorded price match",
                                    systemImage: "cart.badge.questionmark",
                                    description: Text("These stores may still carry the item. Open their known-price lists or try a broader search term.")
                                )
                            }
                        }

                        if !store.stores.isEmpty {
                            Section {
                                ForEach(store.stores) { nearbyStore in
                                    Button { catalogStore = nearbyStore } label: {
                                        NearbyStoreRow(store: nearbyStore)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text("Nearby real stores")
                            } footer: {
                                Text("Open Prices supplies nearby crowdsourced observations; OpenPriceEngine adds current Trader Joe's catalog prices when configured. Repeated store chains are reduced to the closest location.")
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .padding(.top)
            .navigationTitle("Smart store search")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await refreshStores() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(isLoading)
                }
            }
            .task { if store.stores.isEmpty { await refreshStores() } }
            .sheet(item: $catalogStore) { StoreCatalogSheet(store: $0) }
        }
    }

    private func search() async {
        if store.stores.isEmpty { await refreshStores(runSearchAfterLoading: false) }
        plans = ShoppingPlanner.plans(
            for: query.split(separator: ",").map(String.init),
            stores: store.stores,
            preferences: store.preferences,
            reviews: store.reviews,
            budget: budgetStatus
        )
    }

    private func planCard(_ plan: ShoppingPlan) -> some View {
        PlanCard(
            plan: plan,
            recommended: plan.id == plans.first?.id,
            openCatalog: { selectedStore in catalogStore = selectedStore },
            choose: { store.select(plan) }
        )
    }

    private func refreshStores(runSearchAfterLoading: Bool = true) async {
        guard let currentLocation = location.location else {
            errorMessage = "Current location is unavailable. Allow or refresh location access in Settings."
            location.refreshLocation()
            return
        }
        isLoading = true
        errorMessage = nil
        let requestedItems = query.split(separator: ",").map(String.init)
        var nearby: [GroceryStore] = []
        var failures: [String] = []

        do {
            nearby.append(contentsOf: try await OpenPricesService.nearbyStores(around: currentLocation))
        } catch {
            failures.append("Open Prices: \(error.localizedDescription)")
        }
        if OpenPriceEngineService.isConfigured {
            do {
                nearby.append(contentsOf: try await OpenPriceEngineService.nearbyStores(
                    around: currentLocation,
                    matching: requestedItems
                ))
            } catch {
                failures.append("OpenPriceEngine: \(error.localizedDescription)")
            }
        }

        nearby = OpenPricesService.deduplicatedClosestStores(nearby)
        store.stores = nearby
        if nearby.isEmpty {
            errorMessage = failures.isEmpty
                ? "No grocery prices were found within 30 km."
                : "Could not load shop prices. \(failures.joined(separator: " · "))"
        } else {
            if !failures.isEmpty { errorMessage = failures.joined(separator: " · ") }
            if runSearchAfterLoading {
                plans = ShoppingPlanner.plans(
                    for: requestedItems,
                    stores: nearby,
                    preferences: store.preferences,
                    reviews: store.reviews,
                    budget: budgetStatus
                )
            }
        }
        isLoading = false
    }
}

private struct NearbyStoreRow: View {
    let store: GroceryStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "storefront.fill")
                .foregroundStyle(Color.appBlue)
                .frame(width: 32, height: 32)
                .background(Color.appBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.name).font(.headline)
                if let address = store.address { Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Text("\(store.distanceMiles, specifier: "%.1f") mi · \(store.offers.count) recorded prices")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appBlue)
                if let source = store.source { Text(source).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct PlanCard: View {
    let plan: ShoppingPlan
    let recommended: Bool
    let openCatalog: (GroceryStore) -> Void
    let choose: () -> Void
    @EnvironmentObject private var store: AppStore
    @State private var reviewStore: GroceryStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    if recommended { Text("RECOMMENDED FOR YOU").font(.caption.bold()).foregroundStyle(Color.appBlue) }
                    Text(plan.title).font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(plan.estimatedCost, format: .currency(code: "USD")).bold()
                    Text("~\(plan.travelMinutes) min").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(plan.stops) { stop in
                HStack(alignment: .top) {
                    Image(systemName: "storefront").foregroundStyle(Color.appBlue)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stop.store.name).bold()
                        ForEach(stop.products) { product in
                            HStack {
                                Text(product.product).font(.subheadline)
                                Spacer()
                                Text(product.price, format: .currency(code: "USD"))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                        }
                        HStack {
                            Text("\(stop.store.distanceMiles, specifier: "%.1f") mi · ~\(stop.store.travelMinutes) min")
                            if let rating = store.averageRating(for: stop.store.name) {
                                Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill").foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("All recorded prices") { openCatalog(stop.store) }
                            Button("Reviews") { reviewStore = stop.store }
                        }
                        .font(.caption)
                    }
                }
            }
            ForEach(Array(plan.substitutions.keys.sorted()), id: \.self) { item in
                Label("Try \(plan.substitutions[item]!) instead of \(item)", systemImage: "arrow.triangle.swap")
                    .font(.subheadline).foregroundStyle(.orange)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text("Pros").bold()
                    ForEach(plan.pros, id: \.self) { Label($0, systemImage: "plus.circle.fill").foregroundStyle(Color.appBlue) }
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Cons").bold()
                    ForEach(plan.cons, id: \.self) { Label($0, systemImage: "minus.circle.fill").foregroundStyle(.orange) }
                }
            }
            .font(.caption)
            Button("Choose this plan", action: choose).buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 10)
        .sheet(item: $reviewStore) { ReviewSheet(store: $0) }
    }
}

private struct StoreCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: GroceryStore
    @State private var filter = ""

    private var offers: [ProductOffer] {
        guard !filter.isEmpty else { return store.offers }
        return store.offers.filter { $0.product.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let address = store.address { Text(address).font(.footnote).foregroundStyle(.secondary) }
                    LabeledContent("Distance", value: String(format: "%.1f miles", store.distanceMiles))
                    LabeledContent("Recorded products", value: "\(store.offers.count)")
                }
                Section("Recorded products and prices") {
                    ForEach(offers) { offer in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(offer.product).font(.body.weight(.medium))
                                Spacer()
                                Text(offer.price, format: .currency(code: "USD"))
                                    .font(.system(.body, design: .rounded, weight: .bold)).monospacedDigit()
                            }
                            HStack {
                                Text(offer.category.rawValue)
                                Spacer()
                                if let date = offer.observedDate { Text("Last seen \(date.formatted(date: .abbreviated, time: .omitted))") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .searchable(text: $filter, prompt: "Search recorded products")
            .navigationTitle(store.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .bottom) {
                Text(sourceNotice)
                    .font(.caption2).foregroundStyle(.secondary).padding(10)
                    .frame(maxWidth: .infinity).background(.bar)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var sourceNotice: String {
        if store.source == OpenPriceEngineService.sourceName {
            return "Catalog prices supplied by OpenPriceEngine. A listed product or price is not guaranteed at every physical location."
        }
        return "Crowdsourced observations from the last 180 days via Open Prices / Open Food Facts. Availability and current shelf prices are not guaranteed."
    }
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
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Button { rating = star } label: {
                                Image(systemName: star <= rating ? "star.fill" : "star").foregroundStyle(.orange)
                            }.buttonStyle(.plain)
                        }
                    }
                    TextField("What should other shoppers know?", text: $comment, axis: .vertical)
                    Button("Post review") {
                        appStore.addReview(storeName: store.name, rating: rating, comment: comment)
                        comment = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                Section("Shop reviews") {
                    if appStore.reviews(for: store.name).isEmpty { Text("No reviews yet. Be the first.").foregroundStyle(.secondary) }
                    ForEach(appStore.reviews(for: store.name)) { review in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(review.username).bold()
                                Spacer()
                                Text(String(repeating: "★", count: review.rating)).foregroundStyle(.orange)
                            }
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
