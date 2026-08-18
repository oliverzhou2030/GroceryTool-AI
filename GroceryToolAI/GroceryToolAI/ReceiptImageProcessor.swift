import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
@preconcurrency import Vision

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
        let straightened = straighten(normalized)
        let cropped = cropToPrintedContent(straightened)
        let lifted = cropped.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": 0.9, "inputHighlightAmount": 0.8])
        let cleaned = lifted
            .applyingFilter("CIDocumentEnhancer", parameters: [kCIInputAmountKey: 0.12])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0, kCIInputContrastKey: 1.05, kCIInputBrightnessKey: 0.05])
        guard let originalData = jpegData(from: normalized, quality: 0.88), let cleanedData = jpegData(from: cleaned, quality: 0.92) else { throw CocoaError(.fileWriteUnknown) }
        return ReceiptImagePair(original: originalData, cleaned: cleanedData)
    }

    private static func straighten(_ image: CIImage) -> CIImage {
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else { return image }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 8
        rectangleRequest.minimumAspectRatio = 0.14
        rectangleRequest.maximumAspectRatio = 0.72
        rectangleRequest.minimumSize = 0.18
        rectangleRequest.minimumConfidence = 0.65
        rectangleRequest.quadratureTolerance = 30
        try? handler.perform([rectangleRequest])
        let detectedRectangle = rectangleRequest.results?
            .filter { $0.boundingBox.width * $0.boundingBox.height > 0.16 }
            .max { first, second in
                first.boundingBox.width * first.boundingBox.height < second.boundingBox.width * second.boundingBox.height
            }
        guard let rectangle = detectedRectangle else { return image }
        func vector(_ point: CGPoint) -> CIVector {
            let paddedX = min(1, max(0, point.x + (point.x < 0.5 ? -0.015 : 0.015)))
            let paddedY = min(1, max(0, point.y + (point.y < 0.5 ? -0.01 : 0.01)))
            return CIVector(x: extent.minX + paddedX * extent.width, y: extent.minY + paddedY * extent.height)
        }
        let corrected = image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": vector(rectangle.topLeft),
            "inputTopRight": vector(rectangle.topRight),
            "inputBottomLeft": vector(rectangle.bottomLeft),
            "inputBottomRight": vector(rectangle.bottomRight)
        ])
        let correctedArea = corrected.extent.width * corrected.extent.height
        let originalArea = extent.width * extent.height
        return correctedArea > originalArea * 0.12 ? translatedToOrigin(corrected) : image
    }

    private static func cropToPrintedContent(_ image: CIImage) -> CIImage {
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else { return image }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.minimumTextHeight = 0.006
        try? VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
        let observations = (request.results ?? []).filter {
            guard let candidate = $0.topCandidates(1).first else { return false }
            return candidate.confidence > 0.25 && candidate.string.count > 1
        }
        guard observations.count >= 4 else { return image }

        let printedBounds = observations.map { observation in
            let box = observation.boundingBox
            return CGRect(
                x: extent.minX + box.minX * extent.width,
                y: extent.minY + box.minY * extent.height,
                width: box.width * extent.width,
                height: box.height * extent.height
            )
        }.reduce(CGRect.null) { $0.union($1) }

        let horizontalPadding = max(28, printedBounds.width * 0.07)
        let crop = CGRect(
            x: printedBounds.minX - horizontalPadding,
            y: extent.minY,
            width: printedBounds.width + horizontalPadding * 2,
            height: extent.height
        ).intersection(extent).integral
        guard !crop.isNull, crop.width * crop.height > extent.width * extent.height * 0.08 else { return image }
        return translatedToOrigin(image.cropped(to: crop))
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
