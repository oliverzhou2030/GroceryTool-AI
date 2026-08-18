import Foundation
@preconcurrency import Vision
import CoreGraphics
import ImageIO
import PDFKit

enum ReceiptCleaner {
    private static let moneyPattern = #"(?:\$\s*)?([0-9]+(?:\.[0-9]{2}))\s*$"#

    static func clean(text: String, date: Date = .now) -> GroceryReceipt {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let merchant = lines.first(where: { $0.rangeOfCharacter(from: .letters) != nil }) ?? "Unknown Store"
        var items: [ReceiptItem] = []
        var tax = 0.0
        var discount = 0.0
        for line in lines {
            guard let match = line.range(of: moneyPattern, options: .regularExpression),
                  let value = Double(line[match].replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) else { continue }
            let lower = line.lowercased()
            if lower.contains("tax") { tax = value; continue }
            if lower.contains("discount") || lower.contains("coupon") || lower.contains("saving") { discount += value; continue }
            if lower.contains("total") || lower.contains("subtotal") || lower.contains("change") || lower.contains("cash") { continue }
            let name = String(line[..<match.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard name.count > 1 else { continue }
            items.append(ReceiptItem(name: name.capitalized, category: category(for: name), unitPrice: value, total: value))
        }
        return GroceryReceipt(merchant: merchant.capitalized, date: date, items: items, tax: tax, discount: discount, sourceText: text)
    }

    static func category(for name: String) -> GroceryCategory {
        let text = name.lowercased()
        if ["chip", "cookie", "candy", "snack", "cracker"].contains(where: text.contains) { return .snack }
        if ["milk", "cheese", "yogurt", "cream"].contains(where: text.contains) { return .dairy }
        if ["apple", "banana", "lettuce", "onion", "fruit", "vegetable"].contains(where: text.contains) { return .produce }
        if ["cola", "soda", "water", "juice", "coffee", "tea"].contains(where: text.contains) { return .beverage }
        if ["bread", "bagel", "muffin"].contains(where: text.contains) { return .bakery }
        if ["beef", "chicken", "pork", "fish"].contains(where: text.contains) { return .meat }
        return .pantry
    }
}

enum ReceiptOCRService {
    static func recognize(imageData: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        return try await recognize(cgImage: image)
    }

    static func recognize(fileURL: URL) async throws -> String {
        if fileURL.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
            var text = ""
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let image = render(page: page) else { continue }
                text += try await recognize(cgImage: image) + "\n"
            }
            return text
        }
        return try await recognize(imageData: Data(contentsOf: fileURL))
    }

    private static func recognize(cgImage image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2.0
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}

enum AnalyticsService {
    static func analyze(_ receipts: [GroceryReceipt], from: Date, through: Date) -> SpendingAnalytics {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through)) ?? through
        return SpendingAnalytics(receipts: receipts.filter { $0.date >= calendar.startOfDay(for: from) && $0.date < end })
    }
}

enum SpreadsheetExporter {
    static func csv(receipts: [GroceryReceipt]) -> String {
        var rows = [["Date", "Store", "Item", "Category", "Quantity", "Unit Price", "Line Total", "Receipt Total"]]
        let formatter = ISO8601DateFormatter()
        for receipt in receipts.sorted(by: { $0.date < $1.date }) {
            for item in receipt.items {
                rows.append([formatter.string(from: receipt.date), receipt.merchant, item.name, item.category.rawValue, String(item.quantity), String(format: "%.2f", item.unitPrice), String(format: "%.2f", item.total), String(format: "%.2f", receipt.total)])
            }
        }
        let analytics = SpendingAnalytics(receipts: receipts)
        rows += [["", "SUMMARY", "Total spend", "", "", "", "", String(format: "%.2f", analytics.total)], ["", "SUMMARY", "Food : snack ratio", "", "", "", "", String(format: "%.2f", analytics.foodSnackRatio)]]
        for (store, amount) in analytics.storeTotals { rows.append(["", "STORE RATIO", store, "", "", "", "", String(format: "%.2f%%", analytics.total == 0 ? 0 : amount / analytics.total * 100)]) }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
    }
    nonisolated private static func escape(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}

enum ShoppingPlanner {
    static func plans(for queries: [String], stores: [GroceryStore], preferences: UserPreferences, reviews: [StoreReview] = []) -> [ShoppingPlan] {
        let wanted = queries.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let ratingBonus: (String) -> Double = { name in
            let ratings = reviews.filter { $0.storeName == name }.map(\.rating)
            guard !ratings.isEmpty else { return 0 }
            return Double(ratings.reduce(0, +)) / Double(ratings.count)
        }
        var results: [ShoppingPlan] = []
        for store in stores {
            let matched = wanted.compactMap { query in store.offers.first { $0.product.lowercased().contains(query) } }
            if matched.count == wanted.count {
                let pref = preferences.storeWeights[store.name, default: 0]
                results.append(ShoppingPlan(title: "One stop at \(store.name)", stops: [PlanStop(store: store, products: matched)], missing: [], substitutions: [:], score: Double(store.travelMinutes) + matched.reduce(0) { $0 + $1.price } - pref * 4 - ratingBonus(store.name), pros: ["Gets everything in one stop", pref > 0 ? "Matches your store preference" : "Simple trip"], cons: store.travelMinutes > 20 ? ["Longer drive"] : []))
            }
        }
        for firstIndex in stores.indices { for secondIndex in stores.indices where secondIndex > firstIndex {
            let pair = [stores[firstIndex], stores[secondIndex]]
            var stops: [PlanStop] = []; var missing: [String] = []
            for store in pair { let found = wanted.compactMap { q in store.offers.first { $0.product.lowercased().contains(q) } }; if !found.isEmpty { stops.append(PlanStop(store: store, products: found)) } }
            for q in wanted where !stops.flatMap(\.products).contains(where: { $0.product.lowercased().contains(q) }) { missing.append(q) }
            if missing.isEmpty {
                let preferenceBonus = pair.reduce(0.0) { $0 + preferences.storeWeights[$1.name, default: 0] * 3 + ratingBonus($1.name) }
                results.append(ShoppingPlan(title: "Split between \(pair[0].name) + \(pair[1].name)", stops: stops, missing: [], substitutions: [:], score: Double(stops.reduce(0) { $0 + $1.store.travelMinutes }) + stops.flatMap(\.products).reduce(0) { $0 + $1.price } - preferenceBonus, pros: ["All requested products available", "May reduce product cost"], cons: ["Requires two stops"]))
            }
        }}
        if results.isEmpty {
            for store in stores.sorted(by: { $0.travelMinutes < $1.travelMinutes }) {
                var subs: [String: String] = [:]; var offers: [ProductOffer] = []; var missing: [String] = []
                for query in wanted {
                    if let exact = store.offers.first(where: { $0.product.lowercased().contains(query) }) { offers.append(exact) }
                    else if let alternative = store.offers.first(where: { $0.alternatives.contains(where: { $0.lowercased().contains(query) }) }) { offers.append(alternative); subs[query] = alternative.product }
                    else { missing.append(query) }
                }
                if !offers.isEmpty { results.append(ShoppingPlan(title: "Nearby alternatives at \(store.name)", stops: [PlanStop(store: store, products: offers)], missing: missing, substitutions: subs, score: Double(store.travelMinutes) + 15 + Double(missing.count * 20) - ratingBonus(store.name), pros: ["Nearest practical option", "Offers similar products"], cons: missing.isEmpty ? ["Uses substitutions"] : ["Some items unavailable"])) }
            }
        }
        return results.sorted { $0.score < $1.score }
    }
}
