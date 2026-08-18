import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ReceiptsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var draft: GroceryReceipt?
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var showingManual = false
    @State private var showingFiles = false
    @State private var selectedReceiptID: UUID?
    @State private var draftImages: ReceiptImagePair?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedReceiptID) {
                Section {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) { Label("Choose from Photos", systemImage: "photo.on.rectangle.angled") }
                        .onChange(of: photoItems) { _, items in Task { await importPhotos(items) } }
                    Button { showingFiles = true } label: { Label("Choose image or PDF from Files", systemImage: "folder") }
                    Button { showingManual = true } label: { Label("Enter receipt manually", systemImage: "square.and.pencil") }
                }
                Section("Receipt history") {
                    if store.receipts.isEmpty {
                        Text("No saved receipts yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.receipts) { receipt in NavigationLink(value: receipt.id) { ReceiptRow(receipt: receipt) } }
                            .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Receipts")
            .overlay { if isReading { ProgressView("Reading receipt…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        } detail: {
            if let selectedReceipt { ReceiptDetailView(receipt: selectedReceipt) { store.delete(id: selectedReceipt.id); selectedReceiptID = nil } }
            else { ContentUnavailableView("No receipt selected", systemImage: "receipt", description: Text("Import, enter, or select a receipt from history.")) }
        }
        .sheet(item: $draft, onDismiss: { draftImages = nil }) { receipt in ReceiptEditor(receipt: receipt) { store.add($0, images: draftImages); draft = nil; draftImages = nil } }
        .sheet(isPresented: $showingManual) { ReceiptEditor(receipt: GroceryReceipt(merchant: "", date: .now, items: [])) { store.add($0); showingManual = false } }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
            Task { await importFiles(result) }
        }
        .alert("Couldn’t read receipt", isPresented: .constant(errorMessage != nil), actions: { Button("OK") { errorMessage = nil } }, message: { Text(errorMessage ?? "") })
    }

    private var selectedReceipt: GroceryReceipt? {
        guard let selectedReceiptID else { return nil }
        return store.receipts.first { $0.id == selectedReceiptID }
    }

    private func delete(at offsets: IndexSet) {
        let deletedIDs = offsets.map { store.receipts[$0].id }
        store.delete(at: offsets)
        if let selectedReceiptID, deletedIDs.contains(selectedReceiptID) { self.selectedReceiptID = nil }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }; isReading = true
        defer { isReading = false; photoItems = [] }
        do {
            var combined = ""
            var firstImageData: Data?
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    if firstImageData == nil { firstImageData = data }
                    combined += try await ReceiptOCRService.recognize(imageData: data) + "\n"
                }
            }
            guard !combined.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            if let firstImageData { draftImages = try ReceiptImageProcessor.prepare(imageData: firstImageData) }
            draft = ReceiptCleaner.clean(text: combined)
        } catch { errorMessage = error.localizedDescription }
    }


    private func importFiles(_ result: Result<[URL], Error>) async {
        isReading = true
        defer { isReading = false }
        do {
            let urls = try result.get()
            var combined = ""
            var firstImages: ReceiptImagePair?
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if firstImages == nil { firstImages = try ReceiptImageProcessor.prepare(fileURL: url) }
                combined += try await ReceiptOCRService.recognize(fileURL: url) + "\n"
            }
            guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            draftImages = firstImages
            draft = ReceiptCleaner.clean(text: combined)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ReceiptRow: View {
    let receipt: GroceryReceipt
    var body: some View { HStack { VStack(alignment: .leading) { Text(receipt.merchant).font(.headline); Text(receipt.date, style: .date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(receipt.total, format: .currency(code: "USD")).fontWeight(.semibold) } }
}

struct ReceiptDetailView: View {
    @EnvironmentObject private var store: AppStore
    let receipt: GroceryReceipt
    let onDelete: () -> Void
    @State private var confirmingDelete = false
    @State private var imageMode = ReceiptImageMode.cleaned
    @State private var showingFullImage = false

    private var displayedImageURL: URL? {
        store.imageURL(filename: imageMode == .cleaned ? receipt.cleanedImageFilename : receipt.originalImageFilename)
    }

    var body: some View {
        List {
            if receipt.cleanedImageFilename != nil || receipt.originalImageFilename != nil {
                Section("Receipt image") {
                    Picker("Image", selection: $imageMode) {
                        ForEach(ReceiptImageMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let displayedImageURL {
                        ReceiptStoredImage(url: displayedImageURL)
                            .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 520)
                            .contentShape(Rectangle())
                            .onTapGesture { showingFullImage = true }
                        Label(imageMode == .cleaned ? "Whitened and enhanced for easier reading" : "Original imported receipt", systemImage: imageMode == .cleaned ? "wand.and.stars" : "photo")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Receipt image") {
                    Label("No image was saved for this older or manually entered receipt. Re-import the photo to add Original and Cleaned views.", systemImage: "photo.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Date", value: receipt.date.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Items", value: "\(receipt.items.count)")
            }
            Section("Clean bill") {
                ForEach(receipt.items) { item in
                    HStack {
                        VStack(alignment: .leading) { Text(item.name); Text(item.category.rawValue).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(item.total, format: .currency(code: "USD"))
                    }
                }
            }
            Section {
                LabeledContent("Subtotal", value: receipt.subtotal.formatted(.currency(code: "USD")))
                LabeledContent("Tax", value: receipt.tax.formatted(.currency(code: "USD")))
                LabeledContent("Total", value: receipt.total.formatted(.currency(code: "USD"))).fontWeight(.bold)
            }
        }
        .navigationTitle(receipt.merchant)
        .toolbar { ToolbarItem { Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete receipt", systemImage: "trash") } } }
        .confirmationDialog("Delete this receipt?", isPresented: $confirmingDelete, titleVisibility: .visible) { Button("Delete receipt", role: .destructive, action: onDelete) }
        .sheet(isPresented: $showingFullImage) {
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    if let displayedImageURL { ReceiptStoredImage(url: displayedImageURL).padding() }
                }
                .background(Color.black)
                .navigationTitle(imageMode.rawValue + " receipt")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFullImage = false } } }
            }
        }
    }
}

private enum ReceiptImageMode: String, CaseIterable, Identifiable {
    case cleaned = "Cleaned"
    case original = "Original"
    var id: String { rawValue }
}

private struct ReceiptStoredImage: View {
    let url: URL
    var body: some View {
        Group {
            #if os(iOS)
            if let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().interpolation(.high).scaledToFit() }
            else { ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark") }
            #else
            if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
            else { ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark") }
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    ForEach($receipt.items) { $item in HStack { TextField("Item", text: $item.name); TextField("Qty", value: $item.quantity, format: .number).frame(width: 48); Picker("Category", selection: $item.category) { ForEach(GroceryCategory.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden(); TextField("Price", value: $item.total, format: .number.precision(.fractionLength(2))).frame(width: 80) } }
                    .onDelete { receipt.items.remove(atOffsets: $0) }
                    Button("Add item", systemImage: "plus") { receipt.items.append(ReceiptItem(name: "", category: .other, unitPrice: 0, total: 0)) }
                }
                Section("Totals") { TextField("Tax", value: $receipt.tax, format: .number.precision(.fractionLength(2))); TextField("Discount", value: $receipt.discount, format: .number.precision(.fractionLength(2))); LabeledContent("Total", value: receipt.total.formatted(.currency(code: "USD"))) }
            }
            .navigationTitle("Clean receipt")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(receipt); dismiss() }.disabled(receipt.merchant.isEmpty || receipt.items.isEmpty) } }
        }
        #if os(macOS)
        .frame(minWidth: 650, minHeight: 500)
        #endif
    }
}
