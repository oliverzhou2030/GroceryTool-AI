import Foundation
import CoreLocation

enum OpenPricesService {
    static let sourceName = "Open Prices / Open Food Facts"
    static let maximumPriceAgeDays = 180
    private static let baseURL = URL(string: "https://prices.openfoodfacts.org/api/v1")!
    private static let groceryLocationTypes = Set(["supermarket", "convenience", "wholesale", "greengrocer", "deli"])

    static func nearbyStores(around userLocation: CLLocation, radiusKilometers: Double = 30) async throws -> [GroceryStore] {
        let locations: NearbyLocationsResponse = try await request(
            path: "locations/nearby",
            query: [
                URLQueryItem(name: "lat", value: String(userLocation.coordinate.latitude)),
                URLQueryItem(name: "lon", value: String(userLocation.coordinate.longitude)),
                URLQueryItem(name: "radius_km", value: String(radiusKilometers)),
                URLQueryItem(name: "size", value: "30")
            ]
        )

        let candidates = locations.items
            .filter { groceryLocationTypes.contains($0.osmTagValue.lowercased()) && $0.priceCount > 0 }
            .prefix(10)

        return try await withThrowingTaskGroup(of: GroceryStore?.self) { group in
            for location in candidates {
                group.addTask { try await store(for: location) }
            }
            var stores: [GroceryStore] = []
            for try await store in group {
                if let store { stores.append(store) }
            }
            return deduplicatedClosestStores(stores)
        }
    }

    static func deduplicatedClosestStores(_ stores: [GroceryStore]) -> [GroceryStore] {
        var seenNames = Set<String>()
        return stores.sorted { $0.distanceMiles < $1.distanceMiles }.filter { store in
            let normalizedName = store.name
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined()
            return seenNames.insert(normalizedName).inserted
        }
    }

    private static func store(for location: LocationDTO) async throws -> GroceryStore? {
        var allPrices: [PriceDTO] = []
        var page = 1
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -maximumPriceAgeDays, to: .now) ?? .distantPast
        let cutoffString = DateFormatter.openPricesDate.string(from: cutoff)
        repeat {
            let response: PricesResponse = try await request(
                path: "prices",
                query: [
                    URLQueryItem(name: "location_id", value: String(location.id)),
                    URLQueryItem(name: "currency", value: "USD"),
                    URLQueryItem(name: "date__gte", value: cutoffString),
                    URLQueryItem(name: "order_by", value: "-date"),
                    URLQueryItem(name: "size", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )
            allPrices.append(contentsOf: response.items)
            guard page < min(response.pages, 5) else { break }
            page += 1
        } while true

        var latestByProduct: [String: ProductOffer] = [:]
        for price in allPrices {
            guard price.price > 0,
                  let name = price.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            let key = (price.productCode ?? name).lowercased()
            let observedDate = DateFormatter.openPricesDate.date(from: price.date)
            if let current = latestByProduct[key],
               let currentDate = current.observedDate,
               let observedDate,
               currentDate >= observedDate { continue }
            latestByProduct[key] = ProductOffer(
                product: name,
                price: price.price,
                category: ReceiptCleaner.category(for: name),
                alternatives: alternatives(for: name),
                observedDate: observedDate,
                source: sourceName
            )
        }

        guard !latestByProduct.isEmpty else { return nil }
        let miles = location.distanceKilometers * 0.621371
        return GroceryStore(
            name: location.name,
            travelMinutes: max(1, Int((miles / 22 * 60).rounded())),
            distanceMiles: miles,
            offers: latestByProduct.values.sorted { $0.product.localizedCaseInsensitiveCompare($1.product) == .orderedAscending },
            address: location.displayName,
            source: sourceName
        )
    }

    private static func request<Response: Decodable>(path: String, query: [URLQueryItem]) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("GroceryToolAI/1.0 (github.com/oliverzhou2030/GroceryTool-AI)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data)
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

private struct NearbyLocationsResponse: Decodable {
    let items: [LocationDTO]
}

private struct LocationDTO: Decodable {
    let id: Int
    let distanceKilometers: Double
    let osmName: String?
    let osmBrand: String?
    let displayName: String
    let osmTagValue: String
    let priceCount: Int

    var name: String { osmName ?? osmBrand ?? "Unknown Store" }

    enum CodingKeys: String, CodingKey {
        case id
        case distanceKilometers = "distance_km"
        case osmName = "osm_name"
        case osmBrand = "osm_brand"
        case displayName = "osm_display_name"
        case osmTagValue = "osm_tag_value"
        case priceCount = "price_count"
    }
}

private struct PricesResponse: Decodable {
    let items: [PriceDTO]
    let pages: Int
}

private struct PriceDTO: Decodable {
    let product: ProductDTO?
    let productCode: String?
    let productName: String?
    let price: Double
    let date: String

    var displayName: String? { product?.productName ?? productName }

    enum CodingKeys: String, CodingKey {
        case product, price, date
        case productCode = "product_code"
        case productName = "product_name"
    }
}

private struct ProductDTO: Decodable {
    let productName: String?
    enum CodingKeys: String, CodingKey { case productName = "product_name" }
}

private extension DateFormatter {
    static let openPricesDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
