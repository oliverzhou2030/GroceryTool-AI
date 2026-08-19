import SwiftUI

struct ReceiptCalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDates: Set<DateComponents> = [
        Calendar.current.dateComponents([.calendar, .year, .month, .day], from: .now)
    ]
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var rangeEnd = Date.now

    private var selectedReceipts: [GroceryReceipt] {
        store.receipts.filter { receipt in
            let receiptDay = Calendar.current.dateComponents([.calendar, .year, .month, .day], from: receipt.date)
            return selectedDates.contains(receiptDay)
        }.sorted { $0.date > $1.date }
    }
    private var selectedTotal: Double {
        selectedReceipts.reduce(0) { $0 + $1.total }
    }
    private var receiptDates: Set<DateComponents> {
        Set(store.receipts.map { Calendar.current.dateComponents([.calendar, .year, .month, .day], from: $0.date) })
    }
    private var selectionTitle: String {
        switch selectedDates.count {
        case 0: "Selected receipts"
        case 1:
            if let components = selectedDates.first, let date = Calendar.current.date(from: components) {
                "Receipts on \(date.formatted(date: .abbreviated, time: .omitted))"
            } else {
                "Selected receipts"
            }
        default: "Receipts on \(selectedDates.count) selected dates"
        }
    }
    private var rangeAnalytics: SpendingAnalytics {
        AnalyticsService.analyze(store.receipts, from: rangeStart, through: rangeEnd)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GroupBox("Receipt calendar") {
                        VStack(alignment: .leading, spacing: 10) {
                            MultiSelectCalendar(selection: $selectedDates, receiptDates: receiptDates)
                            Label("Tap dates to select them. Tap a selected date again to deselect it.", systemImage: "hand.tap")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            HStack {
                                LabeledContent("Selected dates", value: "\(selectedDates.count)")
                                Spacer()
                                Button("Clear") { selectedDates.removeAll() }
                                    .disabled(selectedDates.isEmpty)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GroupBox(selectionTitle) {
                        VStack(spacing: 0) {
                            if selectedDates.isEmpty {
                                ContentUnavailableView("No dates selected", systemImage: "calendar.badge.minus", description: Text("Tap one or more dates in the calendar."))
                                    .frame(minHeight: 150)
                            } else if selectedReceipts.isEmpty {
                                ContentUnavailableView("No receipts", systemImage: "calendar.badge.minus", description: Text("Choose another date or import a receipt."))
                                    .frame(minHeight: 150)
                            } else {
                                HStack {
                                    LabeledContent("Selected total", value: selectedTotal.formatted(.currency(code: "USD")))
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                Divider()
                                ForEach(selectedReceipts) { receipt in
                                    NavigationLink {
                                        ReceiptDetailView(receipt: receipt) { store.delete(id: receipt.id) }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(receipt.merchant).font(.headline)
                                                Text("\(receipt.date.formatted(date: .abbreviated, time: .omitted)) · \(receipt.items.count) items")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(receipt.total, format: .currency(code: "USD")).fontWeight(.semibold)
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                    if receipt.id != selectedReceipts.last?.id { Divider() }
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

private struct MultiSelectCalendar: View {
    @Binding var selection: Set<DateComponents>
    let receiptDates: Set<DateComponents>
    @State private var displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var calendar: Calendar { Calendar.current }
    private var monthInterval: DateInterval { calendar.dateInterval(of: .month, for: displayedMonth)! }
    private var numberOfDays: Int { calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 0 }
    private var leadingBlankDays: Int {
        let weekday = calendar.component(.weekday, from: monthInterval.start)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { moveMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { moveMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(0..<leadingBlankDays, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                ForEach(1...numberOfDays, id: \.self) { day in dayButton(day) }
            }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)!
        let components = calendar.dateComponents([.calendar, .year, .month, .day], from: date)
        let isSelected = selection.contains(components)
        let hasReceipt = receiptDates.contains(components)
        return Button {
            if isSelected { selection.remove(components) } else { selection.insert(components) }
        } label: {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.system(.body, design: .rounded, weight: isSelected ? .bold : .regular))
                Circle()
                    .fill(hasReceipt ? (isSelected ? Color.white : Color.appBlue) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.appBlue : Color.clear, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
        .accessibilityValue(isSelected ? "Selected" : (hasReceipt ? "Has receipts" : "Not selected"))
    }

    private func moveMonth(by value: Int) {
        if let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = month
        }
    }
}
