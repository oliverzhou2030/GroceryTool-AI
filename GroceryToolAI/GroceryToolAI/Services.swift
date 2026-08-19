import Foundation
@preconcurrency import Vision
import CoreGraphics
import ImageIO
import PDFKit

enum ReceiptCleaner {
    private static let moneyPattern = #"(?i)(?:\$|S)?\s*([0-9]+[\.,][0-9]{2})(?:\s*[A-Z]{1,3})?\s*$"#
    private static let quantityPattern = #"^\s*([0-9]+(?:\.[0-9]+)?)\s+(.+)$"#

    static func clean(text: String, date suppliedDate: Date? = nil) -> GroceryReceipt {
        let rawLines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lines = mergeSplitSummaryLines(rawLines)
        let merchant = merchantName(from: lines)
        var items: [ReceiptItem] = []
        var tax = 0.0
        var discount = 0.0
        var pendingItem: (name: String, quantity: Double)?
        var consumedItemLines = Set<Int>()
        for (index, line) in lines.enumerated() {
            if consumedItemLines.contains(index) { continue }
            let lower = line.lowercased()
            if let match = line.range(of: moneyPattern, options: .regularExpression), let value = moneyValue(in: String(line[match])) {
                if lower.contains("tax") { tax = value; pendingItem = nil; continue }
                if lower.contains("discount") || lower.contains("coupon") || lower.contains("saving") { discount += value; pendingItem = nil; continue }
                if lower.contains("total") || lower.contains("subtotal") || lower.contains("change") || lower.contains("payment") || lower.contains("amount") { pendingItem = nil; continue }

                let beforePrice = String(line[..<match.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                let parsed = itemNameAndQuantity(from: beforePrice) ?? (beforePrice, 1)
                var item: (name: String, quantity: Double)? = parsed.name.isEmpty ? pendingItem : parsed
                if parsed.name.isEmpty && item == nil {
                    for nextIndex in (index + 1)..<min(index + 3, lines.count) {
                        if let next = itemNameAndQuantity(from: lines[nextIndex]), isLikelyItemName(next.name) {
                            item = next
                            consumedItemLines.insert(nextIndex)
                            break
                        }
                    }
                }
                if let item, isLikelyPricedItemName(item.name) {
                    let cleanName = cleanedItemName(item.name)
                    items.append(ReceiptItem(name: cleanName, category: category(for: cleanName), quantity: item.quantity, unitPrice: value / max(1, item.quantity), total: value))
                }
                pendingItem = nil
            } else if line.range(of: quantityPattern, options: .regularExpression) != nil,
                      let parsed = itemNameAndQuantity(from: line), isLikelyItemName(parsed.name) {
                pendingItem = parsed
            }
        }
        return GroceryReceipt(merchant: merchant, date: suppliedDate ?? receiptDate(from: text) ?? .now, items: items, tax: tax, discount: discount, sourceText: text)
    }

    static func category(for name: String) -> GroceryCategory {
        let text = name.lowercased()
        if ["kitkat", "kit kat", "chocolate", "chip", "cookie", "candy", "snack", "cracker", "biscuit", "wafer", "gummy", "popcorn"].contains(where: text.contains) { return .snack }
        if ["milk", "cheese", "yogurt", "cream", "reddi wip", "whipped", "butter", "egg"].contains(where: text.contains) { return .dairy }
        if ["cola", "soda", "water", "juice", "coffee", "tea", "drink", "beverage", "cider"].contains(where: text.contains) { return .beverage }
        if ["mushroom", "enoki", "apple", "banana", "lettuce", "onion", "fruit", "vegetable", "tomato", "potato", "carrot", "broccoli", "spinach", "avocado"].contains(where: text.contains) { return .produce }
        if ["ramen", " rame", "samyang", "noodle", "rice", "pasta", "sauce", "bamboo shoot", "cereal", "flour", "sugar", "oil"].contains(where: text.contains) { return .pantry }
        if ["bread", "bagel", "muffin", "croissant", "cake", "bakery"].contains(where: text.contains) { return .bakery }
        if ["beef", "chicken", "pork", "fish", "salmon", "shrimp", "turkey", "lamb"].contains(where: text.contains) { return .meat }
        if ["frozen", "ice cream", "pizza"].contains(where: text.contains) { return .frozen }
        if ["soap", "detergent", "tissue", "paper towel", "cleaner", "trash bag", "shampoo"].contains(where: text.contains) { return .household }
        return .pantry
    }

    private static func moneyValue(in text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "S", with: "").replacingOccurrences(of: "s", with: "").replacingOccurrences(of: ",", with: ".")
        return normalized.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }.first
    }

    private static func itemNameAndQuantity(from text: String) -> (name: String, quantity: Double)? {
        guard let range = text.range(of: quantityPattern, options: .regularExpression) else { return text.isEmpty ? nil : (text, 1) }
        let matched = String(text[range])
        let pieces = matched.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard pieces.count == 2, let quantity = Double(pieces[0]) else { return (text, 1) }
        return (String(pieces[1]), quantity)
    }

    private static func cleanedItemName(_ text: String) -> String {
        text.replacingOccurrences(of: #"^[#*\-\s]+|[#*\-\s]+$"#, with: "", options: .regularExpression).lowercased().capitalized
    }

    private static func isLikelyItemName(_ text: String) -> Bool {
        let lower = text.lowercased()
        let excluded = ["station", "cashier", "subtotal", "total", "tax", "item count", "payment", "amount", "auth", "visa", "credit", "change"]
        return text.count > 2 && text.rangeOfCharacter(from: .letters) != nil && !excluded.contains(where: lower.contains)
    }

    private static func mergeSplitSummaryLines(_ lines: [String]) -> [String] {
        let summaryLabels = ["subtotal", "tax", "total", "payment", "amount", "change", "discount"]
        var merged: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let lower = line.lowercased()
            if index + 1 < lines.count,
               summaryLabels.contains(where: lower.contains),
               line.range(of: moneyPattern, options: .regularExpression) == nil,
               lines[index + 1].range(of: moneyPattern, options: .regularExpression) != nil {
                merged.append(line + " " + lines[index + 1])
                index += 2
            } else {
                merged.append(line)
                index += 1
            }
        }
        return merged
    }

    private static func isLikelyPricedItemName(_ text: String) -> Bool {
        guard isLikelyItemName(text), !text.contains("/"), !text.contains("\\"), !text.contains("%") else { return false }
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.count >= 2 { return true }
        guard let word = words.first, word.count >= 4 else { return false }
        return word.allSatisfy { $0.isLetter || $0 == "-" }
    }

    private static func merchantName(from lines: [String]) -> String {
        let candidates = lines.prefix(10).filter { line in
            let lower = line.lowercased()
            return line.rangeOfCharacter(from: .letters) != nil &&
                !["station", "cashier", "blvd", "street", "road", "avenue"].contains(where: lower.contains) &&
                line.range(of: #"\d{1,2}/\d{1,2}/\d{2,4}"#, options: .regularExpression) == nil
        }
        if candidates.contains(where: {
            let normalized = $0.lowercased().replacingOccurrences(of: " ", with: "")
            return normalized.contains("jmart") || normalized.contains("j-mart") || normalized.contains("i-mart") || normalized.contains("/mart")
        }) { return "J-Mart Little Neck" }
        let storeWords = ["market", "mart", "grocery", "foods", "supermarket", "costco", "walmart", "target", "aldi", "lidl"]
        let result = candidates.first(where: { candidate in storeWords.contains(where: candidate.lowercased().contains) }) ?? candidates.first ?? "Unknown Store"
        return result.lowercased().capitalized
    }

    private static func receiptDate(from text: String) -> Date? {
        let patterns = [#"\b\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}(?::\d{2})?\b"#, #"\b\d{1,2}/\d{1,2}/\d{4}\b"#, #"\b\d{4}-\d{1,2}-\d{1,2}\b"#]
        let formats = ["MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy", "yyyy-MM-dd"]
        for pattern in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let value = String(text[range])
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .current
                formatter.dateFormat = format
                if let date = formatter.date(from: value) { return date }
            }
        }
        return nil
    }
}

enum ReceiptOCRService {
    static func recognize(imageData: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        return try await recognize(cgImage: image, orientation: orientation)
    }

    static func recognize(fileURL: URL) async throws -> String {
        if fileURL.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
            var text = ""
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let image = render(page: page) else { continue }
                text += try await recognize(cgImage: image, orientation: .up) + "\n"
            }
            return text
        }
        return try await recognize(imageData: Data(contentsOf: fileURL))
    }

    private static func recognize(cgImage image: CGImage, orientation: CGImagePropertyOrientation) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]
            request.customWords = ["J-Mart", "KITKAT", "ENOKI", "SAMYANG", "REDDI WIP"]
            request.minimumTextHeight = 0.006
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request]) }
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
            let matched = wanted.compactMap { query in bestMatch(in: store.offers, for: query) }
            if matched.count == wanted.count {
                let pref = preferences.storeWeights[store.name, default: 0]
                results.append(ShoppingPlan(title: "One stop at \(store.name)", stops: [PlanStop(store: store, products: matched)], missing: [], substitutions: [:], score: Double(store.travelMinutes) + matched.reduce(0) { $0 + $1.price } - pref * 4 - ratingBonus(store.name), pros: ["Gets everything in one stop", pref > 0 ? "Matches your store preference" : "Simple trip"], cons: store.travelMinutes > 20 ? ["Longer drive"] : []))
            }
        }
        for firstIndex in stores.indices { for secondIndex in stores.indices where secondIndex > firstIndex {
            let pair = [stores[firstIndex], stores[secondIndex]]
            var stops: [PlanStop] = []; var missing: [String] = []
            for store in pair { let found = wanted.compactMap { q in bestMatch(in: store.offers, for: q) }; if !found.isEmpty { stops.append(PlanStop(store: store, products: found)) } }
            for q in wanted where bestMatch(in: stops.flatMap(\.products), for: q) == nil { missing.append(q) }
            if missing.isEmpty && stops.count == 2 {
                let preferenceBonus = pair.reduce(0.0) { $0 + preferences.storeWeights[$1.name, default: 0] * 3 + ratingBonus($1.name) }
                results.append(ShoppingPlan(title: "Split between \(pair[0].name) + \(pair[1].name)", stops: stops, missing: [], substitutions: [:], score: Double(stops.reduce(0) { $0 + $1.store.travelMinutes }) + stops.flatMap(\.products).reduce(0) { $0 + $1.price } - preferenceBonus, pros: ["All requested products available", "May reduce product cost"], cons: ["Requires two stops"]))
            }
        }}
        if results.isEmpty {
            for store in stores.sorted(by: { $0.travelMinutes < $1.travelMinutes }) {
                var subs: [String: String] = [:]; var offers: [ProductOffer] = []; var missing: [String] = []
                for query in wanted {
                    if let exact = bestMatch(in: store.offers, for: query) { offers.append(exact) }
                    else if let alternative = store.offers.first(where: { $0.alternatives.contains(where: { $0.lowercased().contains(query) }) }) { offers.append(alternative); subs[query] = alternative.product }
                    else { missing.append(query) }
                }
                if !offers.isEmpty { results.append(ShoppingPlan(title: "Nearby alternatives at \(store.name)", stops: [PlanStop(store: store, products: offers)], missing: missing, substitutions: subs, score: Double(store.travelMinutes) + 15 + Double(missing.count * 20) - ratingBonus(store.name), pros: ["Nearest practical option", "Offers similar products"], cons: missing.isEmpty ? ["Uses substitutions"] : ["Some items unavailable"])) }
            }
        }
        return results.sorted { $0.score < $1.score }
    }

    private static func bestMatch(in offers: [ProductOffer], for query: String) -> ProductOffer? {
        offers
            .filter { productMatches($0.product, query: query) }
            .min { matchScore($0, query: query) < matchScore($1, query: query) }
    }

    private static func matchScore(_ offer: ProductOffer, query: String) -> Int {
        let name = offer.product.lowercased()
        var score = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
        if name == query { score -= 100 }
        if name.hasPrefix("\(query) ") || name.hasSuffix(" \(query)") { score -= 20 }
        if query == "milk" {
            if offer.category == .dairy { score -= 25 }
            if ["almond", "coconut", "oat", "soy", "chocolate", "yogurt", "candy", "pretzel"].contains(where: name.contains) {
                score += 100
            }
        }
        return score
    }

    private static func productMatches(_ product: String, query: String) -> Bool {
        let productWords = words(in: product)
        let queryWords = words(in: query)
        guard !queryWords.isEmpty, productWords.count >= queryWords.count else { return false }
        if queryWords == ["milk"] {
            let nonMilkProducts = Set(["bar", "candy", "cheese", "chocolate", "cookie", "cookies", "cream", "dressing", "ice", "mozzarella", "pretzel", "pretzels", "ricotta", "yogurt"])
            if !nonMilkProducts.isDisjoint(with: productWords) { return false }
            guard let milkIndex = productWords.firstIndex(of: "milk") else { return false }
            let followingWords = productWords.dropFirst(milkIndex + 1)
            if let nextWord = followingWords.first {
                let liquidMilkDescriptors = Set(["1", "2", "fat", "free", "from", "gallon", "half", "lactose", "percent", "quart", "skim", "whole"])
                if !liquidMilkDescriptors.contains(nextWord) { return false }
            }
        }
        if queryWords.count == 1 { return productWords.contains(queryWords[0]) }
        return (0...(productWords.count - queryWords.count)).contains { start in
            Array(productWords[start..<(start + queryWords.count)]) == queryWords
        }
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
