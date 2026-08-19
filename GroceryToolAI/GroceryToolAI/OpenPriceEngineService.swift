import Foundation
import CoreLocation
import MapKit

enum OpenPriceEngineService {
    static let sourceName = "OpenPriceEngine"
    private static let baseURL = URL(string: "https://openpricengine.com/api/v1")!
    private static let supportedUSStore = "Traderjoes"

    static var isConfigured: Bool {
        apiKey != nil
    }

    static func nearbyStores(
        around userLocation: CLLocation,
        matching requestedItems: [String],
        radiusKilometers: Double = 30
    ) async throws -> [GroceryStore] {
        guard apiKey != nil else { return [] }
        let queries = requestedItems
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !queries.isEmpty else { return [] }

        async let offersRequest = offers(matching: queries)
        async let mapItemsRequest = nearbyTraderJoes(around: userLocation, radiusKilometers: radiusKilometers)
        let (offers, mapItems) = try await (offersRequest, mapItemsRequest)
        guard !offers.isEmpty, let closest = mapItems.first else { return [] }

        let storeLocation = closest.placemark.location ?? CLLocation(latitude: closest.placemark.coordinate.latitude, longitude: closest.placemark.coordinate.longitude)
        let miles = userLocation.distance(from: storeLocation) / 1_609.344
        return [GroceryStore(
            name: closest.name ?? "Trader Joe's",
            travelMinutes: max(1, Int((miles / 22 * 60).rounded())),
            distanceMiles: miles,
            offers: offers,
            address: closest.placemark.title,
            source: sourceName
        )]
    }

    static func offers(matching requestedItems: [String]) async throws -> [ProductOffer] {
        var responses: [OpenPriceProduct] = []
        for item in requestedItems {
            responses.append(contentsOf: try await requestProducts(matching: item))
        }

        var newestByName: [String: ProductOffer] = [:]
        for product in responses {
            guard let newest = product.prices.compactMap({ point -> (Date, Double)? in
                guard point.price > 0, let date = DateFormatter.openPriceEngineDate.date(from: point.date) else { return nil }
                return (date, point.price)
            }).max(by: { $0.0 < $1.0 }) else { continue }
            let normalizedName = product.productName.lowercased()
            let candidate = ProductOffer(
                product: product.productName,
                price: newest.1,
                category: ReceiptCleaner.category(for: product.productName),
                alternatives: alternatives(for: product.productName),
                observedDate: newest.0,
                source: sourceName
            )
            if let existing = newestByName[normalizedName],
               let existingDate = existing.observedDate,
               existingDate >= newest.0 { continue }
            newestByName[normalizedName] = candidate
        }
        return newestByName.values.sorted { $0.product.localizedCaseInsensitiveCompare($1.product) == .orderedAscending }
    }

    private static func requestProducts(matching item: String) async throws -> [OpenPriceProduct] {
        guard let apiKey else { return [] }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("\(supportedUSStore)/products/prices/today"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "productname", value: item),
            URLQueryItem(name: "currency", value: "USD")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return [] }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(OpenPriceErrorResponse.self, from: data).detail)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenPriceEngineError.requestFailed(statusCode: http.statusCode, detail: detail)
        }
        return try JSONDecoder().decode([OpenPriceProduct].self, from: data)
    }

    private static func nearbyTraderJoes(around location: CLLocation, radiusKilometers: Double) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Trader Joe's grocery store"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusKilometers * 2_000,
            longitudinalMeters: radiusKilometers * 2_000
        )
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
            .filter { item in
                guard let itemLocation = item.placemark.location else { return false }
                return location.distance(from: itemLocation) <= radiusKilometers * 1_000
            }
            .sorted { lhs, rhs in
                let lhsDistance = lhs.placemark.location.map(location.distance(from:)) ?? .greatestFiniteMagnitude
                let rhsDistance = rhs.placemark.location.map(location.distance(from:)) ?? .greatestFiniteMagnitude
                return lhsDistance < rhsDistance
            }
    }

    private static var apiKey: String? {
        let key = ProcessInfo.processInfo.environment["OPENPRICEENGINE_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    private static func alternatives(for productName: String) -> [String] {
        let name = productName.lowercased()
        if ["coca-cola", "coca cola", "pepsi", "cola"].contains(where: name.contains) {
            return ["Coca-Cola", "Pepsi", "cola"]
        }
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if isLiquidMilkName(words) { return ["milk"] }
        if ["potato chips", "corn chips", "tortilla chips"].contains(where: name.contains) { return ["chips"] }
        return []
    }

    private static func isLiquidMilkName(_ words: [String]) -> Bool {
        let nonMilkProducts = Set(["bar", "candy", "cheese", "chocolate", "cookie", "cookies", "cream", "dressing", "ice", "mozzarella", "pretzel", "pretzels", "ricotta", "yogurt"])
        guard nonMilkProducts.isDisjoint(with: words), let milkIndex = words.firstIndex(of: "milk") else { return false }
        guard let nextWord = words.dropFirst(milkIndex + 1).first else { return true }
        return Set(["1", "2", "fat", "free", "from", "gallon", "half", "lactose", "percent", "quart", "skim", "whole"]).contains(nextWord)
    }
}

private enum OpenPriceEngineError: LocalizedError {
    case requestFailed(statusCode: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(statusCode, detail):
            return "Request failed (HTTP \(statusCode)): \(detail)"
        }
    }
}

private struct OpenPriceErrorResponse: Decodable {
    let detail: String
}

private struct OpenPriceProduct: Decodable {
    let productName: String
    let prices: [OpenPricePoint]

    enum CodingKeys: String, CodingKey {
        case productName = "Product Name"
        case prices = "Price over time"
    }
}

private struct OpenPricePoint: Decodable {
    let date: String
    let price: Double

    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case price = "Price"
    }
}

private extension DateFormatter {
    static let openPriceEngineDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
