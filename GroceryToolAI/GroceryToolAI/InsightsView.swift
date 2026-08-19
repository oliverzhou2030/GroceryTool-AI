import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var start = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var end = Date.now
    @State private var chartStyle = InsightChartStyle.bar

    private var analytics: SpendingAnalytics {
        AnalyticsService.analyze(store.receipts, from: start, through: end)
    }
    private var categoryData: [CategoryChartDatum] {
        analytics.categoryItemCounts.enumerated().map {
            CategoryChartDatum(category: $0.element.0, count: $0.element.1, color: InsightPalette.colors[$0.offset % InsightPalette.colors.count])
        }
    }
    private var storeData: [StoreChartDatum] {
        analytics.storeTotals.enumerated().map {
            StoreChartDatum(store: $0.element.0, amount: $0.element.1, color: InsightPalette.colors[$0.offset % InsightPalette.colors.count])
        }
    }
    private var categorySpendData: [CategorySpendChartDatum] {
        analytics.categorySpendTotals.enumerated().map {
            CategorySpendChartDatum(category: $0.element.0, amount: $0.element.1, color: InsightPalette.colors[$0.offset % InsightPalette.colors.count])
        }
    }
    private var categorizedSpendTotal: Double { categorySpendData.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    analysisPeriod
                    metrics
                    chartStylePicker
                    categoryChart
                    categorySpendChart
                    storeChart
                    Text("Use Export CSV for Google Sheets, Microsoft Excel, Numbers, or Files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Spending insights")
        }
    }

    private var analysisPeriod: some View {
        GroupBox("Analysis period") {
            VStack(spacing: 12) {
                DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
                HStack {
                    Label("All insights use this range.", systemImage: "calendar.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let url = store.exportURL(for: analytics.receipts) {
                        ShareLink(
                            item: url,
                            preview: SharePreview("GroceryTool AI receipt ledger")
                        ) {
                            Label("Export CSV for Sheets", systemImage: "tablecells")
                        }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Text("On iPhone, choose Google Drive or Google Sheets in the share menu. On Mac, save the CSV and import it at sheets.google.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155))], spacing: 14) {
            MetricCard(title: "Total spent", value: analytics.total.formatted(.currency(code: "USD")), icon: "dollarsign.circle.fill", accent: .blue)
            MetricCard(title: "Receipts", value: "\(analytics.receipts.count)", icon: "receipt.fill", accent: .mint)
            MetricCard(title: "Food : snack", value: String(format: "%.1f : 1", analytics.foodSnackRatio), icon: "fork.knife.circle.fill", accent: .orange)
        }
    }

    private var chartStylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Chart style", systemImage: "chart.pie.fill").font(.headline)
            Picker("Chart style", selection: $chartStyle) {
                ForEach(InsightChartStyle.allCases) { style in
                    Label(style.title, systemImage: style.icon).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var categoryChart: some View {
        InsightChartCard(title: "Food types", subtitle: "Number of purchased items", icon: "carrot.fill") {
            if categoryData.isEmpty {
                emptyChart
            } else if chartStyle == .pie {
                Chart(categoryData) { datum in
                    SectorMark(
                        angle: .value("Items", datum.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .cornerRadius(5)
                    .foregroundStyle(datum.color.gradient)
                    .annotation(position: .overlay) {
                        Text("\(datum.count)")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 280)
                chartLegend(categoryData.map { (categoryName($0.category), $0.color) })
            } else {
                Chart(categoryData) { datum in
                    BarMark(x: .value("Items", datum.count), y: .value("Category", categoryName(datum.category)))
                        .foregroundStyle(datum.color.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) { chartNumber("\(datum.count)") }
                }
                .frame(height: max(210, CGFloat(categoryData.count * 48)))
            }
        }
    }

    private var storeChart: some View {
        InsightChartCard(title: "Markets", subtitle: "Share of total spending", icon: "storefront.fill") {
            if storeData.isEmpty {
                emptyChart
            } else if chartStyle == .pie {
                Chart(storeData) { datum in
                    SectorMark(
                        angle: .value("Spend", datum.amount),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .cornerRadius(5)
                    .foregroundStyle(datum.color.gradient)
                    .annotation(position: .overlay) {
                        Text(percent(for: datum.amount))
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 280)
                chartLegend(storeData.map { ($0.store, $0.color) })
            } else {
                Chart(storeData) { datum in
                    BarMark(x: .value("Spend", datum.amount), y: .value("Store", datum.store))
                        .foregroundStyle(datum.color.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) { chartNumber(percent(for: datum.amount)) }
                }
                .frame(height: max(210, CGFloat(storeData.count * 55)))
            }
        }
    }

    private var categorySpendChart: some View {
        InsightChartCard(title: "Food spending", subtitle: "Share of item spending by food type", icon: "dollarsign.circle.fill") {
            if categorySpendData.isEmpty {
                emptyChart
            } else if chartStyle == .pie {
                Chart(categorySpendData) { datum in
                    SectorMark(
                        angle: .value("Spend", datum.amount),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .cornerRadius(5)
                    .foregroundStyle(datum.color.gradient)
                    .annotation(position: .overlay) {
                        Text(categoryPercent(for: datum.amount))
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 280)
                chartLegend(categorySpendData.map { (categoryName($0.category), $0.color) })
            } else {
                Chart(categorySpendData) { datum in
                    BarMark(x: .value("Spend", datum.amount), y: .value("Category", categoryName(datum.category)))
                        .foregroundStyle(datum.color.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) { chartNumber(categoryPercent(for: datum.amount)) }
                }
                .frame(height: max(210, CGFloat(categorySpendData.count * 48)))
            }
        }
    }

    private var emptyChart: some View {
        ContentUnavailableView("No receipt data", systemImage: "chart.pie", description: Text("Choose a wider date range or add a receipt."))
            .frame(height: 210)
    }

    private func percent(for amount: Double) -> String {
        analytics.total == 0 ? "0%" : (amount / analytics.total).formatted(.percent.precision(.fractionLength(0)))
    }

    private func categoryPercent(for amount: Double) -> String {
        categorizedSpendTotal == 0 ? "0%" : (amount / categorizedSpendTotal).formatted(.percent.precision(.fractionLength(0)))
    }

    private func categoryName(_ category: GroceryCategory) -> String {
        switch store.preferences.language {
        case .english: category.rawValue
        case .simplifiedChinese:
            switch category {
            case .produce: "蔬果"
            case .dairy: "乳制品"
            case .meat: "肉类"
            case .pantry: "食品杂货"
            case .frozen: "冷冻食品"
            case .bakery: "烘焙食品"
            case .beverage: "饮料"
            case .snack: "零食"
            case .household: "家居用品"
            case .other: "其他"
            }
        case .spanish:
            switch category {
            case .produce: "Frutas y verduras"
            case .dairy: "Lácteos"
            case .meat: "Carne"
            case .pantry: "Despensa"
            case .frozen: "Congelados"
            case .bakery: "Panadería"
            case .beverage: "Bebidas"
            case .snack: "Aperitivos"
            case .household: "Hogar"
            case .other: "Otros"
            }
        }
    }

    private func chartNumber(_ value: String) -> some View {
        Text(value)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
    }

    private func chartLegend(_ entries: [(String, Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 7) {
                    Circle().fill(entry.1).frame(width: 9, height: 9)
                    Text(entry.0).font(.caption).lineLimit(1)
                }
            }
        }
    }
}

private enum InsightChartStyle: String, CaseIterable, Identifiable {
    case bar, pie
    var id: String { rawValue }
    var title: LocalizedStringKey { self == .bar ? "Bar" : "Pie" }
    var icon: String { self == .bar ? "chart.bar.fill" : "chart.pie.fill" }
}

private struct CategoryChartDatum: Identifiable {
    let category: GroceryCategory
    let count: Int
    let color: Color
    var id: GroceryCategory { category }
}

private struct StoreChartDatum: Identifiable {
    let store: String
    let amount: Double
    let color: Color
    var id: String { store }
}

private struct CategorySpendChartDatum: Identifiable {
    let category: GroceryCategory
    let amount: Double
    let color: Color
    var id: GroceryCategory { category }
}

private enum InsightPalette {
    static let colors: [Color] = [.blue, .mint, .orange, .purple, .pink, .cyan, .green, .indigo, .yellow, .teal]
}

private struct InsightChartCard<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.appBlue.gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.appBlue.opacity(0.08), radius: 12, y: 5)
    }
}

private struct MetricCard: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(accent.gradient, in: RoundedRectangle(cornerRadius: 13))
            Text(value)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.16)) }
    }
}
