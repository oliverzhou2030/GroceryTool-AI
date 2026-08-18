import Foundation
import Testing
@testable import GroceryToolAI

struct GroceryToolAITests {
    @Test func receiptCleanerExtractsItemsAndTax() {
        let text = """
        GREEN MARKET
        Whole Milk 3.89
        Potato Chips $4.25
        TAX 0.32
        TOTAL 8.46
        """
        let receipt = ReceiptCleaner.clean(text: text)
        #expect(receipt.merchant == "Green Market")
        #expect(receipt.items.count == 2)
        #expect(receipt.tax == 0.32)
        #expect(receipt.total == 8.46)
        #expect(receipt.items.last?.category == .snack)
    }

    @Test func analyticsFiltersDatesAndComputesRatios() {
        let old = GroceryReceipt(merchant: "Old", date: .distantPast, items: [ReceiptItem(name: "Chips", category: .snack, unitPrice: 5, total: 5)])
        let recent = GroceryReceipt(merchant: "Fresh", date: .now, items: [ReceiptItem(name: "Milk", category: .dairy, unitPrice: 10, total: 10), ReceiptItem(name: "Chips", category: .snack, unitPrice: 5, total: 5)])
        let analytics = AnalyticsService.analyze([old, recent], from: .now.addingTimeInterval(-3600), through: .now)
        #expect(analytics.receipts.count == 1)
        #expect(analytics.total == 15)
        #expect(analytics.foodSnackRatio == 2)
    }

    @Test func spreadsheetContainsExcelCompatibleSummary() {
        let csv = SpreadsheetExporter.csv(receipts: SampleData.receipts)
        #expect(csv.contains("Receipt Total"))
        #expect(csv.contains("Food : snack ratio"))
        #expect(csv.contains("STORE RATIO"))
    }

    @Test func plannerPrefersOneStopAndLearnsStores() {
        var preferences = UserPreferences()
        let first = ShoppingPlanner.plans(for: ["Coca-Cola", "milk"], stores: SampleData.stores, preferences: preferences)
        #expect(first.first?.missing.isEmpty == true)
        #expect(first.contains { $0.stops.count == 1 })
        if let valuePlan = first.first(where: { $0.stops.contains(where: { $0.store.name == "Neighborhood Market" }) }) { preferences.record(plan: valuePlan) }
        #expect(preferences.storeWeights["Neighborhood Market"] == 1)
    }

    @Test func plannerOffersSimilarColaNearby() {
        let pepsiOnly = GroceryStore(name: "Close Store", travelMinutes: 5, distanceMiles: 1, offers: [ProductOffer(product: "Pepsi Cola", price: 2, category: .beverage, alternatives: ["Coca-Cola"])])
        let plans = ShoppingPlanner.plans(for: ["Coca-Cola"], stores: [pepsiOnly], preferences: UserPreferences())
        #expect(plans.first?.substitutions["coca-cola"] == "Pepsi Cola")
    }

    @Test func highlyReviewedStoreReceivesRankingBoost() {
        let equalA = GroceryStore(name: "Blue Shop", travelMinutes: 5, distanceMiles: 1, offers: [ProductOffer(product: "Milk", price: 4, category: .dairy)])
        let equalB = GroceryStore(name: "White Shop", travelMinutes: 5, distanceMiles: 1, offers: [ProductOffer(product: "Milk", price: 4, category: .dairy)])
        let reviews = [StoreReview(storeName: "White Shop", username: "admin", rating: 5, comment: "Reliable")]
        let plans = ShoppingPlanner.plans(for: ["Milk"], stores: [equalA, equalB], preferences: UserPreferences(), reviews: reviews)
        #expect(plans.first?.stops.first?.store.name == "White Shop")
    }
}
