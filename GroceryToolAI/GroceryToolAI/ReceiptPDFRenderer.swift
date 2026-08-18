import Foundation
import CoreGraphics
import CoreText
import ImageIO

enum ReceiptPDFRenderer {
    private static let pageBox = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func render(receipt: GroceryReceipt, cleanedImageData: Data?) -> Data? {
        let data = NSMutableData()
        var mediaBox = pageBox
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let itemsPerPage = 15
        let detailsPageCount = max(1, Int(ceil(Double(receipt.items.count) / Double(itemsPerPage))))
        for pageIndex in 0..<detailsPageCount {
            let start = pageIndex * itemsPerPage
            let end = min(start + itemsPerPage, receipt.items.count)
            let pageItems = start < end ? Array(receipt.items[start..<end]) : []
            context.beginPDFPage(nil)
            drawDocumentPage(
                receipt: receipt,
                items: pageItems,
                pageNumber: pageIndex + 1,
                pageCount: detailsPageCount,
                isLastDetailsPage: pageIndex == detailsPageCount - 1,
                in: context
            )
            context.endPDFPage()
        }

        if let cleanedImageData, let source = CGImageSourceCreateWithData(cleanedImageData as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            context.beginPDFPage(nil)
            drawText("Straightened receipt scan", x: 42, y: 754, size: 20, weight: .bold, color: CGColor(red: 0.12, green: 0.45, blue: 0.72, alpha: 1), in: context)
            let available = CGRect(x: 36, y: 36, width: 540, height: 690)
            let scale = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let rect = CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height)
            context.draw(image, in: rect)
            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    private static func drawDocumentPage(receipt: GroceryReceipt, items: [ReceiptItem], pageNumber: Int, pageCount: Int, isLastDetailsPage: Bool, in context: CGContext) {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(pageBox)
        context.setFillColor(CGColor(red: 0.91, green: 0.97, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 688, width: pageBox.width, height: 104))
        drawText("GroceryTool AI", x: 42, y: 750, size: 13, weight: .bold, color: CGColor(red: 0.12, green: 0.45, blue: 0.72, alpha: 1), in: context)
        drawText("Clean Receipt", x: 42, y: 712, size: 28, weight: .bold, in: context)
        drawText(receipt.merchant, x: 42, y: 658, size: 20, weight: .bold, in: context)
        drawText(receipt.date.formatted(date: .long, time: .shortened), x: 42, y: 634, size: 11, color: CGColor(gray: 0.35, alpha: 1), in: context)
        if pageCount > 1 {
            drawText("Page \(pageNumber) of \(pageCount)", x: 500, y: 634, size: 9, color: CGColor(gray: 0.4, alpha: 1), in: context)
        }

        var y: CGFloat = 594
        drawRule(y: y + 14, in: context)
        drawText("ITEM", x: 42, y: y, size: 9, weight: .bold, color: CGColor(gray: 0.35, alpha: 1), in: context)
        drawText("CATEGORY", x: 372, y: y, size: 9, weight: .bold, color: CGColor(gray: 0.35, alpha: 1), in: context)
        drawText("QTY", x: 470, y: y, size: 9, weight: .bold, color: CGColor(gray: 0.35, alpha: 1), in: context)
        drawText("TOTAL", x: 520, y: y, size: 9, weight: .bold, color: CGColor(gray: 0.35, alpha: 1), in: context)
        y -= 24

        for item in items {
            drawText(item.name, x: 42, y: y, size: 10, in: context)
            drawText(item.category.rawValue, x: 372, y: y, size: 9, color: CGColor(gray: 0.3, alpha: 1), in: context)
            drawText(item.quantity.formatted(.number.precision(.fractionLength(0...2))), x: 470, y: y, size: 9, in: context)
            drawText(item.total.formatted(.currency(code: "USD")), x: 520, y: y, size: 9, weight: .bold, in: context)
            y -= 25
            drawRule(y: y + 9, color: CGColor(gray: 0.9, alpha: 1), in: context)
        }

        guard isLastDetailsPage else {
            drawText("Continued on next page", x: 42, y: 96, size: 10, weight: .bold, color: CGColor(red: 0.12, green: 0.45, blue: 0.72, alpha: 1), in: context)
            drawText("Generated privately on device by GroceryTool AI", x: 42, y: 34, size: 8, color: CGColor(gray: 0.5, alpha: 1), in: context)
            return
        }

        y -= 12
        drawText("Subtotal", x: 400, y: y, size: 11, in: context)
        drawText(receipt.subtotal.formatted(.currency(code: "USD")), x: 520, y: y, size: 11, in: context)
        y -= 23
        drawText("Tax", x: 400, y: y, size: 11, in: context)
        drawText(receipt.tax.formatted(.currency(code: "USD")), x: 520, y: y, size: 11, in: context)
        if receipt.discount > 0 {
            y -= 23
            drawText("Discount", x: 400, y: y, size: 11, in: context)
            drawText("-" + receipt.discount.formatted(.currency(code: "USD")), x: 520, y: y, size: 11, in: context)
        }
        y -= 32
        drawRule(y: y + 15, color: CGColor(red: 0.23, green: 0.62, blue: 0.92, alpha: 1), width: 2, in: context)
        drawText("TOTAL", x: 400, y: y, size: 14, weight: .bold, in: context)
        drawText(receipt.total.formatted(.currency(code: "USD")), x: 510, y: y, size: 16, weight: .bold, color: CGColor(red: 0.12, green: 0.45, blue: 0.72, alpha: 1), in: context)
        drawText("Generated privately on device by GroceryTool AI", x: 42, y: 34, size: 8, color: CGColor(gray: 0.5, alpha: 1), in: context)
    }

    private enum FontWeight { case regular, bold }
    private static func drawText(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: FontWeight = .regular, color: CGColor = CGColor(gray: 0.08, alpha: 1), in context: CGContext) {
        let fontName = weight == .bold ? "Helvetica-Bold" : "Helvetica"
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        guard let value = CFAttributedStringCreate(nil, text as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(value)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }

    private static func drawRule(y: CGFloat, color: CGColor = CGColor(gray: 0.75, alpha: 1), width: CGFloat = 1, in context: CGContext) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.move(to: CGPoint(x: 42, y: y))
        context.addLine(to: CGPoint(x: 570, y: y))
        context.strokePath()
    }
}
