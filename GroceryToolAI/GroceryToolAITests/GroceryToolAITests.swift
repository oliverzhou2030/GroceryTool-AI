import Foundation
import PDFKit
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

    @Test func jMartReceiptExtractsStoreDateWrappedItemsAndCategories() {
        let text = """
        Jmart
        J-Mart little Neck
        249-26 Northern Blvd
        08/18/2026 12:21:09
        1 NESTLE KITKAT GREEN TEA EXT $4.99 FT
        1 CRISPY BAMBOO SHOOTS PEPPER $5.99 F
        1 SHOU LONG KAN INST VEGELLI $3.49 F
        1 DS ENOKI MUSHROOMS MALA
        $5.99 F
        1 SAMYANG 2X HOT CHICKEN RAME $7.99 F
        1 REDDI WIP ORIGINAL CREAMY
        $4.99 F
        Item Count: 6
        Subtotal: $33.44
        Tax: $0.44
        Total: $33.88
        """
        let receipt = ReceiptCleaner.clean(text: text)
        #expect(receipt.merchant == "J-Mart Little Neck")
        #expect(receipt.items.count == 6)
        #expect(receipt.items.first?.category == .snack)
        #expect(receipt.items.first(where: { $0.name.contains("Enoki") })?.category == .produce)
        #expect(receipt.items.first(where: { $0.name.contains("Samyang") })?.category == .pantry)
        #expect(receipt.items.first(where: { $0.name.contains("Reddi") })?.category == .dairy)
        #expect(receipt.total == 33.88)
        #expect(Calendar.current.component(.year, from: receipt.date) == 2026)
        #expect(Calendar.current.component(.month, from: receipt.date) == 8)
        #expect(Calendar.current.component(.day, from: receipt.date) == 18)
    }

    @Test func receiptCleanerAssociatesPricePrintedBeforeItem() {
        let receipt = ReceiptCleaner.clean(text: """
        /mart
        I-Mart little Neck
        08/18/2026 12:21:09
        $5.99 F
        1 DS ENOKI MUSHROOMS MALA
        $4.99 F
        1 REDDI WIP ORIGINAL CREAMY
        Subtotal: $10.98
        Tax: $0.00
        Total: $10.98
        """)
        #expect(receipt.merchant == "J-Mart Little Neck")
        #expect(receipt.items.count == 2)
        #expect(receipt.items[0].name.contains("Enoki"))
        #expect(receipt.items[1].category == .dairy)
        #expect(receipt.total == 10.98)
    }

    @Test func cleanReceiptPDFIncludesEveryDetailPage() throws {
        var receipt = SampleData.receipts[0]
        receipt.items = (1...31).map {
            ReceiptItem(name: "Grocery item \($0)", category: .pantry, unitPrice: 1, total: 1)
        }
        let pdf = try #require(ReceiptPDFRenderer.render(receipt: receipt, cleanedImageData: nil))
        #expect(String(decoding: pdf.prefix(4), as: UTF8.self) == "%PDF")
        #expect(PDFDocument(data: pdf)?.pageCount == 3)
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

    @Test func categoryCorrectionsPersistAndBecomeDefaults() throws {
        var preferences = UserPreferences()
        preferences.learnCategory(itemName: "Nestle KitKat Green Tea", category: .pantry)
        #expect(preferences.learnedCategory(for: "NESTLE KITKAT GREEN-TEA") == .pantry)

        let encoded = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(UserPreferences.self, from: encoded)
        #expect(restored.learnedCategory(for: "Nestle KitKat Green Tea") == .pantry)
    }
}
