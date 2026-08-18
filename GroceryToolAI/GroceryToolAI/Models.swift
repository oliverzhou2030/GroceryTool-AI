import Foundation

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
    var storeTotals: [(String, Double)] {
        Dictionary(grouping: receipts, by: \.merchant).map { ($0.key, $0.value.reduce(0) { $0 + $1.total }) }.sorted { $0.1 > $1.1 }
    }
}
