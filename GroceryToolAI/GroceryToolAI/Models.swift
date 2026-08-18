import Foundation

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

struct LocalAccount: Identifiable, Codable, Equatable {
    var id = UUID()
    var username: String
    var displayName: String
    var passwordHash: String
}

struct StoreReview: Identifiable, Codable, Hashable {
    var id = UUID()
    var storeName: String
    var username: String
    var rating: Int
    var comment: String
    var date = Date()
}

enum GroceryCategory: String, Codable, CaseIterable, Identifiable {
    case produce = "Produce", dairy = "Dairy", meat = "Meat", pantry = "Pantry"
    case frozen = "Frozen", bakery = "Bakery", beverage = "Beverages"
    case snack = "Snacks", household = "Household", other = "Other"
    var id: String { rawValue }
    var isFood: Bool { ![.snack, .household, .other].contains(self) }
}

struct ReceiptItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: GroceryCategory
    var quantity: Double = 1
    var unitPrice: Double
    var total: Double
}

struct GroceryReceipt: Identifiable, Codable, Hashable {
    var id = UUID()
    var merchant: String
    var date: Date
    var items: [ReceiptItem]
    var tax: Double = 0
    var discount: Double = 0
    var sourceText: String = ""
    var originalImageFilename: String?
    var cleanedImageFilename: String?
    var subtotal: Double { items.reduce(0) { $0 + $1.total } }
    var total: Double { max(0, subtotal + tax - discount) }
}

struct ProductOffer: Identifiable, Codable, Hashable {
    var id = UUID()
    var product: String
    var price: Double
    var category: GroceryCategory
    var alternatives: [String] = []
}

struct GroceryStore: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var travelMinutes: Int
    var distanceMiles: Double
    var offers: [ProductOffer]
}

struct PlanStop: Identifiable, Hashable {
    var id = UUID()
    var store: GroceryStore
    var products: [ProductOffer]
}

struct ShoppingPlan: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var stops: [PlanStop]
    var missing: [String]
    var substitutions: [String: String]
    var score: Double
    var estimatedCost: Double { stops.flatMap(\.products).reduce(0) { $0 + $1.price } }
    var travelMinutes: Int { stops.reduce(0) { $0 + $1.store.travelMinutes } }
    var pros: [String]
    var cons: [String]
}

struct UserPreferences: Codable, Equatable {
    var storeWeights: [String: Double] = [:]
    var categorySpend: [GroceryCategory: Double] = [:]
    var selectedPlans: Int = 0
    var theme: AppTheme = .system
    init(storeWeights: [String: Double] = [:], categorySpend: [GroceryCategory: Double] = [:], selectedPlans: Int = 0, theme: AppTheme = .system) {
        self.storeWeights = storeWeights
        self.categorySpend = categorySpend
        self.selectedPlans = selectedPlans
        self.theme = theme
    }
    private enum CodingKeys: String, CodingKey { case storeWeights, categorySpend, selectedPlans, theme }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storeWeights = try container.decodeIfPresent([String: Double].self, forKey: .storeWeights) ?? [:]
        categorySpend = try container.decodeIfPresent([GroceryCategory: Double].self, forKey: .categorySpend) ?? [:]
        selectedPlans = try container.decodeIfPresent(Int.self, forKey: .selectedPlans) ?? 0
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
    }
    mutating func record(plan: ShoppingPlan) {
        selectedPlans += 1
        for stop in plan.stops { storeWeights[stop.store.name, default: 0] += 1 }
    }
}

struct SpendingAnalytics {
    var receipts: [GroceryReceipt]
    var total: Double { receipts.reduce(0) { $0 + $1.total } }
    var foodSpend: Double { lineItems.filter(\.category.isFood).reduce(0) { $0 + $1.total } }
    var snackSpend: Double { lineItems.filter { $0.category == .snack }.reduce(0) { $0 + $1.total } }
    var lineItems: [ReceiptItem] { receipts.flatMap(\.items) }
    var foodSnackRatio: Double { snackSpend == 0 ? foodSpend : foodSpend / snackSpend }
    var categoryItemCounts: [(GroceryCategory, Int)] {
        Dictionary(grouping: lineItems, by: \.category).map { ($0.key, $0.value.count) }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.rawValue < rhs.0.rawValue : lhs.1 > rhs.1
        }
    }
    var storeTotals: [(String, Double)] {
        Dictionary(grouping: receipts, by: \.merchant).map { ($0.key, $0.value.reduce(0) { $0 + $1.total }) }.sorted { $0.1 > $1.1 }
    }
}
