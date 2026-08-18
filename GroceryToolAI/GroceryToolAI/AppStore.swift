import Foundation
import SwiftUI
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published var receipts: [GroceryReceipt] = [] { didSet { save() } }
    @Published var preferences = UserPreferences() { didSet { save() } }
    @Published var stores: [GroceryStore] = SampleData.stores
    private var isLoading = true
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("GroceryToolAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("user-data.json")
        load()
        isLoading = false
        if receipts.isEmpty { receipts = SampleData.receipts }
    }

    func add(_ receipt: GroceryReceipt) { receipts.insert(receipt, at: 0) }
    func delete(at offsets: IndexSet) { receipts.remove(atOffsets: offsets) }
    func select(_ plan: ShoppingPlan) { preferences.record(plan: plan) }
    func exportURL(for receipts: [GroceryReceipt]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GroceryLedger-\(Date().formatted(.iso8601.year().month().day())).csv")
        do { try SpreadsheetExporter.csv(receipts: receipts).write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    private struct Snapshot: Codable { var receipts: [GroceryReceipt]; var preferences: UserPreferences }
    private func load() { guard let data = try? Data(contentsOf: fileURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }; receipts = snapshot.receipts; preferences = snapshot.preferences }
    private func save() { guard !isLoading, let data = try? JSONEncoder().encode(Snapshot(receipts: receipts, preferences: preferences)) else { return }; try? data.write(to: fileURL, options: .atomic) }
}

enum SampleData {
    static let stores = [
        GroceryStore(name: "Neighborhood Market", travelMinutes: 5, distanceMiles: 1.8, offers: [ProductOffer(product: "Coca-Cola 12 pack", price: 8.49, category: .beverage, alternatives: ["Pepsi", "cola"]), ProductOffer(product: "Whole Milk", price: 3.89, category: .dairy), ProductOffer(product: "Pepsi 12 pack", price: 7.49, category: .beverage, alternatives: ["Coca-Cola", "cola"]), ProductOffer(product: "Bananas", price: 1.49, category: .produce)]),
        GroceryStore(name: "Value Foods", travelMinutes: 10, distanceMiles: 4.2, offers: [ProductOffer(product: "Pepsi 12 pack", price: 6.99, category: .beverage, alternatives: ["Coca-Cola", "cola"]), ProductOffer(product: "2% Milk", price: 3.29, category: .dairy), ProductOffer(product: "Potato Chips", price: 3.99, category: .snack)]),
        GroceryStore(name: "Super Center", travelMinutes: 30, distanceMiles: 18.0, offers: [ProductOffer(product: "Coca-Cola 24 pack", price: 12.99, category: .beverage, alternatives: ["Pepsi", "cola"]), ProductOffer(product: "Organic Milk", price: 4.99, category: .dairy), ProductOffer(product: "Apples", price: 4.49, category: .produce), ProductOffer(product: "Chocolate Cookies", price: 4.29, category: .snack)])
    ]
    static let receipts = [GroceryReceipt(merchant: "Neighborhood Market", date: .now.addingTimeInterval(-86400 * 2), items: [ReceiptItem(name: "Whole Milk", category: .dairy, unitPrice: 3.89, total: 3.89), ReceiptItem(name: "Bananas", category: .produce, quantity: 2, unitPrice: 0.75, total: 1.50), ReceiptItem(name: "Potato Chips", category: .snack, unitPrice: 3.99, total: 3.99)], tax: 0.32)]
}
