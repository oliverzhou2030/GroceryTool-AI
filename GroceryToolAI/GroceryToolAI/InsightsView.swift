import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var start = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var end = Date.now
    private var analytics: SpendingAnalytics { AnalyticsService.analyze(store.receipts, from: start, through: end) }
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 20) {
                HStack { DatePicker("From", selection: $start, displayedComponents: .date); DatePicker("Through", selection: $end, displayedComponents: .date); Spacer(); if let url = store.exportURL(for: analytics.receipts) { ShareLink(item: url) { Label("Export CSV", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent) } }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))]) { MetricCard(title: "Total spent", value: analytics.total.formatted(.currency(code: "USD")), icon: "dollarsign.circle"); MetricCard(title: "Receipts", value: "\(analytics.receipts.count)", icon: "receipt"); MetricCard(title: "Food : snack", value: String(format: "%.1f : 1", analytics.foodSnackRatio), icon: "fork.knife") }
                GroupBox("Store spending ratio") { Chart(analytics.storeTotals, id: \.0) { store, amount in BarMark(x: .value("Spend", amount), y: .value("Store", store)).foregroundStyle(.green.gradient).annotation(position: .trailing) { Text(analytics.total == 0 ? "0%" : (amount / analytics.total).formatted(.percent.precision(.fractionLength(0)))) } }.frame(height: max(180, CGFloat(analytics.storeTotals.count * 55))) }.frame(maxWidth: .infinity)
                Text("CSV files open directly in Microsoft Excel and import into Google Sheets.").font(.footnote).foregroundStyle(.secondary)
            }.padding() }.navigationTitle("Spending insights")
        }
    }
}

private struct MetricCard: View { let title: String; let value: String; let icon: String; var body: some View { VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).font(.title2).foregroundStyle(.green); Text(value).font(.title.bold()); Text(title).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.background, in: RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.05), radius: 8) } }
