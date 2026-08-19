import Foundation
import SwiftUI
import Combine
import CryptoKit

@MainActor
final class AppStore: ObservableObject {
    private static let documentProcessingVersion = 2
    @Published var receipts: [GroceryReceipt] = [] { didSet { save() } }
    @Published var preferences = UserPreferences() { didSet { save() } }
    @Published var stores: [GroceryStore] = []
    @Published var accounts: [LocalAccount] = [] { didSet { save() } }
    @Published var reviews: [StoreReview] = [] { didSet { save() } }
    @Published var currentUsername: String?
    private var isLoading = true
    private let fileURL: URL
    private let imagesDirectory: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("GroceryToolAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        imagesDirectory = directory.appendingPathComponent("ReceiptImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("user-data.json")
        load()
        isLoading = false
        removeLegacySampleReceipt()
        seedAdminAccount()
        upgradeReceiptDocuments()
    }

    func add(_ receipt: GroceryReceipt, images: ReceiptImagePair? = nil, learningFrom recognizedReceipt: GroceryReceipt? = nil) {
        if let recognizedReceipt { learnCategoryCorrections(from: recognizedReceipt, to: receipt) }
        var savedReceipt = receipt
        if let images {
            let originalName = "\(receipt.id.uuidString)-original.jpg"
            let cleanedName = "\(receipt.id.uuidString)-cleaned.jpg"
            do {
                try images.original.write(to: imagesDirectory.appendingPathComponent(originalName), options: .atomic)
                try images.cleaned.write(to: imagesDirectory.appendingPathComponent(cleanedName), options: .atomic)
                savedReceipt.originalImageFilename = originalName
                savedReceipt.cleanedImageFilename = cleanedName
            } catch {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(originalName))
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(cleanedName))
            }
        }
        let pdfName = "\(receipt.id.uuidString)-clean-receipt.pdf"
        if let pdf = ReceiptPDFRenderer.render(receipt: savedReceipt, cleanedImageData: images?.cleaned) {
            try? pdf.write(to: imagesDirectory.appendingPathComponent(pdfName), options: .atomic)
            savedReceipt.pdfFilename = pdfName
        }
        savedReceipt.documentProcessingVersion = Self.documentProcessingVersion
        receipts.insert(savedReceipt, at: 0)
    }
    func applyLearnedCategories(to receipt: GroceryReceipt) -> GroceryReceipt {
        var updated = receipt
        for index in updated.items.indices {
            if let learned = preferences.learnedCategory(for: updated.items[index].name) {
                updated.items[index].category = learned
            }
        }
        return updated
    }
    func imageURL(filename: String?) -> URL? {
        guard let filename else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func documentURL(filename: String?) -> URL? { imageURL(filename: filename) }
    func delete(at offsets: IndexSet) {
        let removed = offsets.map { receipts[$0] }
        removed.forEach(removeImages)
        receipts.remove(atOffsets: offsets)
    }
    func delete(id: UUID) {
        receipts.filter { $0.id == id }.forEach(removeImages)
        receipts.removeAll { $0.id == id }
    }
    func select(_ plan: ShoppingPlan) { preferences.record(plan: plan) }
    func signIn(username: String, password: String) -> Bool {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard accounts.contains(where: { $0.username.lowercased() == normalized && $0.passwordHash == Self.hash(password) }) else { return false }
        currentUsername = normalized
        return true
    }
    func createAccount(username: String, displayName: String, password: String) -> String? {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count >= 3 else { return "Username must contain at least 3 characters." }
        guard password.count >= 4 else { return "Password must contain at least 4 characters." }
        guard !accounts.contains(where: { $0.username.lowercased() == normalized }) else { return "That username already exists." }
        accounts.append(LocalAccount(username: normalized, displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalized : displayName, passwordHash: Self.hash(password)))
        currentUsername = normalized
        return nil
    }
    func signOut() { currentUsername = nil }
    func reviews(for storeName: String) -> [StoreReview] { reviews.filter { $0.storeName == storeName }.sorted { $0.date > $1.date } }
    func averageRating(for storeName: String) -> Double? {
        let values = reviews(for: storeName).map(\.rating)
        return values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
    }
    func addReview(storeName: String, rating: Int, comment: String) {
        guard let username = currentUsername else { return }
        reviews.append(StoreReview(storeName: storeName, username: username, rating: min(5, max(1, rating)), comment: comment.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    func exportURL(for receipts: [GroceryReceipt]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GroceryLedger-\(Date().formatted(.iso8601.year().month().day())).csv")
        do { try SpreadsheetExporter.csv(receipts: receipts).write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    private struct Snapshot: Codable {
        var receipts: [GroceryReceipt]
        var preferences: UserPreferences
        var accounts: [LocalAccount] = []
        var reviews: [StoreReview] = []
        init(receipts: [GroceryReceipt], preferences: UserPreferences, accounts: [LocalAccount], reviews: [StoreReview]) {
            self.receipts = receipts
            self.preferences = preferences
            self.accounts = accounts
            self.reviews = reviews
        }
        private enum CodingKeys: String, CodingKey { case receipts, preferences, accounts, reviews }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            receipts = try container.decodeIfPresent([GroceryReceipt].self, forKey: .receipts) ?? []
            preferences = try container.decodeIfPresent(UserPreferences.self, forKey: .preferences) ?? UserPreferences()
            accounts = try container.decodeIfPresent([LocalAccount].self, forKey: .accounts) ?? []
            reviews = try container.decodeIfPresent([StoreReview].self, forKey: .reviews) ?? []
        }
    }
    private func load() {
        guard let data = try? Data(contentsOf: fileURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        receipts = snapshot.receipts
        preferences = snapshot.preferences
        accounts = snapshot.accounts
        reviews = snapshot.reviews
    }
    private func save() {
        guard !isLoading, let data = try? JSONEncoder().encode(Snapshot(receipts: receipts, preferences: preferences, accounts: accounts, reviews: reviews)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    private func seedAdminAccount() {
        guard !accounts.contains(where: { $0.username.lowercased() == "admin" }) else { return }
        accounts.append(LocalAccount(username: "admin", displayName: "Admin", passwordHash: Self.hash("admin")))
    }
    private func learnCategoryCorrections(from recognized: GroceryReceipt, to edited: GroceryReceipt) {
        for editedItem in edited.items {
            guard let originalItem = recognized.items.first(where: { $0.id == editedItem.id }),
                  originalItem.category != editedItem.category else { continue }
            preferences.learnCategory(itemName: editedItem.name, category: editedItem.category)
        }
    }
    private func removeLegacySampleReceipt() {
        receipts.removeAll { receipt in
            receipt.merchant == "Neighborhood Market" &&
            Set(receipt.items.map(\.name)) == Set(["Whole Milk", "Bananas", "Potato Chips"]) &&
            abs(receipt.tax - 0.32) < 0.001
        }
    }
    private func removeImages(for receipt: GroceryReceipt) {
        for filename in [receipt.originalImageFilename, receipt.cleanedImageFilename, receipt.pdfFilename].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(filename))
        }
    }
    private func upgradeReceiptDocuments() {
        var updated = receipts
        var changed = false
        for index in updated.indices where (updated[index].documentProcessingVersion ?? 0) < Self.documentProcessingVersion {
            let filename = updated[index].pdfFilename ?? "\(updated[index].id.uuidString)-clean-receipt.pdf"
            var cleanedData = imageURL(filename: updated[index].cleanedImageFilename).flatMap { try? Data(contentsOf: $0) }
            if let originalURL = imageURL(filename: updated[index].originalImageFilename),
               let originalData = try? Data(contentsOf: originalURL),
               let images = try? ReceiptImageProcessor.prepare(imageData: originalData) {
                let cleanedName = updated[index].cleanedImageFilename ?? "\(updated[index].id.uuidString)-cleaned.jpg"
                try? images.cleaned.write(to: imagesDirectory.appendingPathComponent(cleanedName), options: .atomic)
                updated[index].cleanedImageFilename = cleanedName
                cleanedData = images.cleaned
            }
            if let pdf = ReceiptPDFRenderer.render(receipt: updated[index], cleanedImageData: cleanedData) {
                try? pdf.write(to: imagesDirectory.appendingPathComponent(filename), options: .atomic)
                updated[index].pdfFilename = filename
            }
            updated[index].documentProcessingVersion = Self.documentProcessingVersion
            changed = true
        }
        if changed { receipts = updated }
    }
    private static func hash(_ password: String) -> String {
        SHA256.hash(data: Data("GroceryToolAI.local.\(password)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum SampleData {
    static let stores = [
        GroceryStore(name: "Neighborhood Market", travelMinutes: 5, distanceMiles: 1.8, offers: [ProductOffer(product: "Coca-Cola 12 pack", price: 8.49, category: .beverage, alternatives: ["Pepsi", "cola"]), ProductOffer(product: "Whole Milk", price: 3.89, category: .dairy), ProductOffer(product: "Pepsi 12 pack", price: 7.49, category: .beverage, alternatives: ["Coca-Cola", "cola"]), ProductOffer(product: "Bananas", price: 1.49, category: .produce)]),
        GroceryStore(name: "Value Foods", travelMinutes: 10, distanceMiles: 4.2, offers: [ProductOffer(product: "Pepsi 12 pack", price: 6.99, category: .beverage, alternatives: ["Coca-Cola", "cola"]), ProductOffer(product: "2% Milk", price: 3.29, category: .dairy), ProductOffer(product: "Potato Chips", price: 3.99, category: .snack)]),
        GroceryStore(name: "Super Center", travelMinutes: 30, distanceMiles: 18.0, offers: [ProductOffer(product: "Coca-Cola 24 pack", price: 12.99, category: .beverage, alternatives: ["Pepsi", "cola"]), ProductOffer(product: "Organic Milk", price: 4.99, category: .dairy), ProductOffer(product: "Apples", price: 4.49, category: .produce), ProductOffer(product: "Chocolate Cookies", price: 4.29, category: .snack)])
    ]
    static let receipts = [GroceryReceipt(merchant: "Neighborhood Market", date: .now.addingTimeInterval(-86400 * 2), items: [ReceiptItem(name: "Whole Milk", category: .dairy, unitPrice: 3.89, total: 3.89), ReceiptItem(name: "Bananas", category: .produce, quantity: 2, unitPrice: 0.75, total: 1.50), ReceiptItem(name: "Potato Chips", category: .snack, unitPrice: 3.99, total: 3.99)], tax: 0.32)]
}
