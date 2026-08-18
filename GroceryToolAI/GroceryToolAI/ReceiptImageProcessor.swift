import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ReceiptImagePair {
    let original: Data
    let cleaned: Data
}

enum ReceiptImageProcessor {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func prepare(imageData: Data) throws -> ReceiptImagePair {
        guard let image = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else { throw CocoaError(.fileReadCorruptFile) }
        return try prepare(image: image)
    }

    static func prepare(fileURL: URL) throws -> ReceiptImagePair {
        if fileURL.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: fileURL), let page = document.page(at: 0), let image = render(page: page) else { throw CocoaError(.fileReadCorruptFile) }
            return try prepare(image: CIImage(cgImage: image))
        }
        return try prepare(imageData: Data(contentsOf: fileURL))
    }

    private static func prepare(image: CIImage) throws -> ReceiptImagePair {
        let normalized = resized(image, maximumDimension: 2600)
        let document = normalized.applyingFilter("CIDocumentEnhancer", parameters: [kCIInputAmountKey: 1.0])
        let cleaned = document
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0, kCIInputContrastKey: 1.32, kCIInputBrightnessKey: 0.08])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.28])
        guard let originalData = jpegData(from: normalized, quality: 0.88), let cleanedData = jpegData(from: cleaned, quality: 0.92) else { throw CocoaError(.fileWriteUnknown) }
        return ReceiptImagePair(original: originalData, cleaned: cleanedData)
    }

    private static func resized(_ image: CIImage, maximumDimension: CGFloat) -> CIImage {
        let extent = image.extent
        let largest = max(extent.width, extent.height)
        guard largest > maximumDimension else { return translatedToOrigin(image) }
        let scale = maximumDimension / largest
        return translatedToOrigin(image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
    }

    private static func translatedToOrigin(_ image: CIImage) -> CIImage {
        let extent = image.extent
        return image.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
    }

    private static func jpegData(from image: CIImage, quality: Double) -> Data? {
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2.0
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
