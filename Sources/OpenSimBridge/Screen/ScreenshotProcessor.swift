import CoreGraphics
import Foundation
import ImageIO
import OpenSimCore
import UniformTypeIdentifiers

public struct RenderedScreenshot: Sendable, Equatable {
    public var data: Data
    public var width: Int
    public var height: Int

    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

public struct ScreenshotProcessor: Sendable {
    public init() {}

    public func render(source: URL, format: ScreenshotFormat, scale: Double, quality: Int?) throws -> RenderedScreenshot {
        guard 0.1 <= scale && scale <= 4.0 else {
            throw OpenSimError.invalidArgument("scale must be between 0.1 and 4.0")
        }
        if let quality, format == .png {
            throw OpenSimError.invalidArgument("quality is only supported for JPEG")
        }
        if let quality, !(1..<101).contains(quality) {
            throw OpenSimError.invalidArgument("quality must be between 1 and 100")
        }
        guard let sourceImage = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(sourceImage, 0, nil) else {
            throw OpenSimError(code: .inputFailed, message: "Could not read screenshot")
        }
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OpenSimError(code: .internalError, message: "No image context")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else {
            throw OpenSimError(code: .internalError, message: "No scaled image")
        }
        let data = NSMutableData()
        let type = format == .png ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
            throw OpenSimError(code: .internalError, message: "No image destination")
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(quality ?? 80) / 100
        }
        CGImageDestinationAddImage(destination, scaled, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw OpenSimError(code: .internalError, message: "Encode failed")
        }
        return RenderedScreenshot(data: data as Data, width: width, height: height)
    }
}
