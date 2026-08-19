import Foundation

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case spanish = "es"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .spanish: "Español"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }
}

enum BudgetPeriodUnit: String, Codable, CaseIterable, Identifiable {
    case day = "Days"
    case week = "Weeks"
    case month = "Months"

    var id: String { rawValue }
}

struct GroceryBudget: Codable, Equatable {
    var isEnabled = false
    var amount = 3_000.0
    var periodLength = 1
    var periodUnit = BudgetPeriodUnit.month
}

struct GroceryBudgetStatus: Equatable {
    var amount: Double
    var spent: Double
    var start: Date
    var end: Date

    var remaining: Double { amount - spent }
    var progress: Double { amount > 0 ? spent / amount : 0 }
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
    var pdfFilename: String?
    var documentProcessingVersion: Int?
    var subtotal: Double { items.reduce(0) { $0 + $1.total } }
    var total: Double { max(0, subtotal + tax - discount) }
}

struct ProductOffer: Identifiable, Codable, Hashable {
    var id = UUID()
    var product: String
    var price: Double
    var category: GroceryCategory
    var alternatives: [String] = []
    var observedDate: Date?
    var source: String?
}

struct GroceryStore: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var travelMinutes: Int
    var distanceMiles: Double
    var offers: [ProductOffer]
    var address: String? = nil
    var source: String? = nil
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
    var categoryOverrides: [String: GroceryCategory] = [:]
    var selectedPlans: Int = 0
    var theme: AppTheme = .system
    var language: AppLanguage = .english
    var groceryBudget = GroceryBudget()
    init(storeWeights: [String: Double] = [:], categorySpend: [GroceryCategory: Double] = [:], categoryOverrides: [String: GroceryCategory] = [:], selectedPlans: Int = 0, theme: AppTheme = .system, language: AppLanguage = .english, groceryBudget: GroceryBudget = GroceryBudget()) {
        self.storeWeights = storeWeights
        self.categorySpend = categorySpend
        self.categoryOverrides = categoryOverrides
        self.selectedPlans = selectedPlans
        self.theme = theme
        self.language = language
        self.groceryBudget = groceryBudget
    }
    private enum CodingKeys: String, CodingKey { case storeWeights, categorySpend, categoryOverrides, selectedPlans, theme, language, groceryBudget }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storeWeights = try container.decodeIfPresent([String: Double].self, forKey: .storeWeights) ?? [:]
        categorySpend = try container.decodeIfPresent([GroceryCategory: Double].self, forKey: .categorySpend) ?? [:]
        categoryOverrides = try container.decodeIfPresent([String: GroceryCategory].self, forKey: .categoryOverrides) ?? [:]
        selectedPlans = try container.decodeIfPresent(Int.self, forKey: .selectedPlans) ?? 0
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        groceryBudget = try container.decodeIfPresent(GroceryBudget.self, forKey: .groceryBudget) ?? GroceryBudget()
    }
    mutating func record(plan: ShoppingPlan) {
        selectedPlans += 1
        for stop in plan.stops { storeWeights[stop.store.name, default: 0] += 1 }
    }
    mutating func learnCategory(itemName: String, category: GroceryCategory) {
        categoryOverrides[Self.normalizedItemName(itemName)] = category
    }
    func learnedCategory(for itemName: String) -> GroceryCategory? {
        categoryOverrides[Self.normalizedItemName(itemName)]
    }
    private static func normalizedItemName(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
    var categorySpendTotals: [(GroceryCategory, Double)] {
        let foodItems = lineItems.filter { ![GroceryCategory.household, .other].contains($0.category) }
        return Dictionary(grouping: foodItems, by: \.category).map { category, items in
            (category, items.reduce(0) { $0 + $1.total })
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.rawValue < rhs.0.rawValue : lhs.1 > rhs.1
        }
    }
    var storeTotals: [(String, Double)] {
        Dictionary(grouping: receipts, by: \.merchant).map { ($0.key, $0.value.reduce(0) { $0 + $1.total }) }.sorted { $0.1 > $1.1 }
    }
}
