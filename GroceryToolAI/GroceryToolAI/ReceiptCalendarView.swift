import SwiftUI

struct ReceiptCalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDate = Date.now
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var rangeEnd = Date.now

    private var dayReceipts: [GroceryReceipt] {
        store.receipts.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }.sorted { $0.date > $1.date }
    }
    private var rangeAnalytics: SpendingAnalytics {
        AnalyticsService.analyze(store.receipts, from: rangeStart, through: rangeEnd)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GroupBox("Receipt calendar") {
                        DatePicker("Receipt date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox("Receipts on \(selectedDate.formatted(date: .abbreviated, time: .omitted))") {
                        VStack(spacing: 0) {
                            if dayReceipts.isEmpty {
                                ContentUnavailableView("No receipts", systemImage: "calendar.badge.minus", description: Text("Choose another date or import a receipt."))
                                    .frame(minHeight: 150)
                            } else {
                                ForEach(dayReceipts) { receipt in
                                    NavigationLink {
                                        ReceiptDetailView(receipt: receipt) { store.delete(id: receipt.id) }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(receipt.merchant).font(.headline)
                                                Text("\(receipt.items.count) items").font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(receipt.total, format: .currency(code: "USD")).fontWeight(.semibold)
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                    if receipt.id != dayReceipts.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox("Spending date range") {
                        VStack(spacing: 14) {
                            DatePicker("From", selection: $rangeStart, in: ...rangeEnd, displayedComponents: .date)
                            DatePicker("Through", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                            Divider()
                            LabeledContent("Receipts", value: "\(rangeAnalytics.receipts.count)")
                            LabeledContent("Total spent", value: rangeAnalytics.total.formatted(.currency(code: "USD"))).fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color.appBackground)
            .navigationTitle("Receipt calendar")
        }
    }
}
