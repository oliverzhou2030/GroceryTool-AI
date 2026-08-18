import SwiftUI
import PhotosUI

struct ReceiptsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var draft: GroceryReceipt?
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var showingManual = false

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) { Label("Scan receipt photos", systemImage: "camera.viewfinder") }
                        .onChange(of: photoItems) { _, items in Task { await importPhotos(items) } }
                    Button { showingManual = true } label: { Label("Enter receipt manually", systemImage: "square.and.pencil") }
                }
                Section("Receipt history") {
                    ForEach(store.receipts) { receipt in NavigationLink(value: receipt.id) { ReceiptRow(receipt: receipt) } }
                        .onDelete(perform: store.delete)
                }
            }
            .navigationTitle("Receipts")
            .overlay { if isReading { ProgressView("Reading receipt…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        } detail: {
            if let first = store.receipts.first { ReceiptDetailView(receipt: first) } else { ContentUnavailableView("No receipts", systemImage: "receipt", description: Text("Scan or enter your first receipt.")) }
        }
        .sheet(item: $draft) { receipt in ReceiptEditor(receipt: receipt) { store.add($0); draft = nil } }
        .sheet(isPresented: $showingManual) { ReceiptEditor(receipt: GroceryReceipt(merchant: "", date: .now, items: [])) { store.add($0); showingManual = false } }
        .alert("Couldn’t read receipt", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }; isReading = true
        defer { isReading = false; photoItems = [] }
        do {
            var combined = ""
            for item in items { if let data = try await item.loadTransferable(type: Data.self) { combined += try await ReceiptOCRService.recognize(imageData: data) + "\n" } }
            guard !combined.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            draft = ReceiptCleaner.clean(text: combined)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ReceiptRow: View {
    let receipt: GroceryReceipt
    var body: some View { HStack { VStack(alignment: .leading) { Text(receipt.merchant).font(.headline); Text(receipt.date, style: .date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(receipt.total, format: .currency(code: "USD")).fontWeight(.semibold) } }
}

struct ReceiptDetailView: View {
    let receipt: GroceryReceipt
    var body: some View {
        List { Section { LabeledContent("Date", value: receipt.date.formatted(date: .abbreviated, time: .omitted)); LabeledContent("Items", value: "\(receipt.items.count)") }; Section("Clean bill") { ForEach(receipt.items) { item in HStack { VStack(alignment: .leading) { Text(item.name); Text(item.category.rawValue).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(item.total, format: .currency(code: "USD")) } } }; Section { LabeledContent("Subtotal", value: receipt.subtotal.formatted(.currency(code: "USD"))); LabeledContent("Tax", value: receipt.tax.formatted(.currency(code: "USD"))); LabeledContent("Total", value: receipt.total.formatted(.currency(code: "USD"))).fontWeight(.bold) } }
        .navigationTitle(receipt.merchant)
    }
}

struct ReceiptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var receipt: GroceryReceipt
    let onSave: (GroceryReceipt) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Receipt") { TextField("Store", text: $receipt.merchant); DatePicker("Date", selection: $receipt.date, displayedComponents: .date) }
                Section("Items") {
                    ForEach($receipt.items) { $item in HStack { TextField("Item", text: $item.name); Picker("Category", selection: $item.category) { ForEach(GroceryCategory.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden(); TextField("Price", value: $item.total, format: .number.precision(.fractionLength(2))).frame(width: 80) } }
                    .onDelete { receipt.items.remove(atOffsets: $0) }
                    Button("Add item", systemImage: "plus") { receipt.items.append(ReceiptItem(name: "", category: .other, unitPrice: 0, total: 0)) }
                }
                Section("Totals") { TextField("Tax", value: $receipt.tax, format: .number.precision(.fractionLength(2))); TextField("Discount", value: $receipt.discount, format: .number.precision(.fractionLength(2))); LabeledContent("Total", value: receipt.total.formatted(.currency(code: "USD"))) }
            }
            .navigationTitle("Clean receipt")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(receipt); dismiss() }.disabled(receipt.merchant.isEmpty || receipt.items.isEmpty) } }
        }.frame(minWidth: 650, minHeight: 500)
    }
}
