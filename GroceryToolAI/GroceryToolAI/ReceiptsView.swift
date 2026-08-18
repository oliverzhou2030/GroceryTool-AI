import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ReceiptsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var activeDraft: ReceiptImportDraft?
    @State private var pendingDrafts: [ReceiptImportDraft] = []
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var showingManual = false
    @State private var showingFiles = false
    @State private var selectedReceiptID: UUID?

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
        .sheet(item: $activeDraft, onDismiss: presentNextDraft) { draft in
            ReceiptEditor(receipt: draft.receipt) {
                store.add($0, images: draft.images, learningFrom: draft.receipt)
                activeDraft = nil
            }
        }
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
            var imported: [ReceiptImportDraft] = []
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let images = try ReceiptImageProcessor.prepare(imageData: data)
                    let text = try await ReceiptOCRService.recognize(imageData: data)
                    let receipt = store.applyLearnedCategories(to: ReceiptCleaner.clean(text: text))
                    imported.append(ReceiptImportDraft(receipt: receipt, images: images))
                }
            }
            guard !imported.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            present(imported)
        } catch { errorMessage = error.localizedDescription }
    }


    private func importFiles(_ result: Result<[URL], Error>) async {
        isReading = true
        defer { isReading = false }
        do {
            let urls = try result.get()
            var imported: [ReceiptImportDraft] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let images = try ReceiptImageProcessor.prepare(fileURL: url)
                let text = try await ReceiptOCRService.recognize(fileURL: url)
                let receipt = store.applyLearnedCategories(to: ReceiptCleaner.clean(text: text))
                imported.append(ReceiptImportDraft(receipt: receipt, images: images))
            }
            guard !imported.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            present(imported)
        } catch { errorMessage = error.localizedDescription }
    }

    private func present(_ drafts: [ReceiptImportDraft]) {
        guard !drafts.isEmpty else { return }
        if activeDraft == nil {
            activeDraft = drafts[0]
            pendingDrafts.append(contentsOf: drafts.dropFirst())
        } else {
            pendingDrafts.append(contentsOf: drafts)
        }
    }

    private func presentNextDraft() {
        guard !pendingDrafts.isEmpty else { return }
        let next = pendingDrafts.removeFirst()
        Task { @MainActor in
            await Task.yield()
            activeDraft = next
        }
    }
}

private struct ReceiptImportDraft: Identifiable {
    let id = UUID()
    let receipt: GroceryReceipt
    let images: ReceiptImagePair
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
    @State private var documentMode = ReceiptDocumentMode.pdf
    @State private var showingFullImage = false

    private var displayedDocumentURL: URL? {
        switch documentMode {
        case .pdf: store.documentURL(filename: receipt.pdfFilename)
        case .original: store.imageURL(filename: receipt.originalImageFilename)
        }
    }

    var body: some View {
        List {
            if receipt.pdfFilename != nil || receipt.originalImageFilename != nil {
                Section("Receipt document") {
                    Picker("Document", selection: $documentMode) {
                        if receipt.pdfFilename != nil { Text("PDF").tag(ReceiptDocumentMode.pdf) }
                        if receipt.originalImageFilename != nil { Text("Original").tag(ReceiptDocumentMode.original) }
                    }
                    .pickerStyle(.segmented)
                    if let displayedDocumentURL {
                        Group {
                            if documentMode == .pdf { ReceiptPDFView(url: displayedDocumentURL) }
                            else { ReceiptStoredImage(url: displayedDocumentURL) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 560)
                        .contentShape(Rectangle())
                        .onTapGesture { showingFullImage = true }
                        Label(documentDescription, systemImage: documentMode == .pdf ? "doc.richtext" : "photo")
                            .font(.caption).foregroundStyle(.secondary)
                        if let pdfURL = store.documentURL(filename: receipt.pdfFilename) {
                            ShareLink(item: pdfURL) { Label("Share clean receipt PDF", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
            } else {
                Section("Receipt image") {
                    Label("No original image was saved for this older or manually entered receipt. Re-import the photo to add an Original view.", systemImage: "photo.badge.exclamationmark")
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
        .onAppear { if receipt.pdfFilename == nil { documentMode = .original } }
        .toolbar { ToolbarItem { Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete receipt", systemImage: "trash") } } }
        .confirmationDialog("Delete this receipt?", isPresented: $confirmingDelete, titleVisibility: .visible) { Button("Delete receipt", role: .destructive, action: onDelete) }
        .sheet(isPresented: $showingFullImage) {
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    if let displayedDocumentURL {
                        if documentMode == .pdf { ReceiptPDFView(url: displayedDocumentURL).frame(minWidth: 560, minHeight: 760).padding() }
                        else { ReceiptStoredImage(url: displayedDocumentURL).padding() }
                    }
                }
                .background(documentMode == .pdf ? Color.white : Color.black)
                .navigationTitle(documentMode.rawValue + " receipt")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFullImage = false } } }
            }
        }
    }

    private var documentDescription: String {
        switch documentMode {
        case .pdf: "Formatted receipt PDF with store, date, categorized items, totals, and a straightened scan"
        case .original: "Original imported receipt"
        }
    }
}

private enum ReceiptDocumentMode: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case original = "Original"
    var id: String { rawValue }
}

#if os(iOS)
private struct ReceiptPDFView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displaysPageBreaks = true; return view }
    func updateUIView(_ view: PDFView, context: Context) { if view.document?.documentURL != url { view.document = PDFDocument(url: url) } }
}
#else
private struct ReceiptPDFView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displaysPageBreaks = true; return view }
    func updateNSView(_ view: PDFView, context: Context) { if view.document?.documentURL != url { view.document = PDFDocument(url: url) } }
}
#endif

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
