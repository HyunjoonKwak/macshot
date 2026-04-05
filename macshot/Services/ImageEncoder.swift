import Cocoa
import UniformTypeIdentifiers
import ImageIO
import WebP

/// Shared image encoding with user-configurable format, quality, and resolution.
enum ImageEncoder {

    enum Format: String {
        case png = "png"
        case jpeg = "jpeg"
        case heic = "heic"
        case webp = "webp"
    }

    static var format: Format {
        if let raw = UserDefaults.standard.string(forKey: "imageFormat"),
           let fmt = Format(rawValue: raw) {
            return fmt
        }
        return .png
    }

    /// Lossy quality 0.0–1.0 (used for JPEG, HEIC, and WebP)
    static var quality: CGFloat {
        if let q = UserDefaults.standard.object(forKey: "imageQuality") as? Double {
            return CGFloat(max(0.1, min(1.0, q)))
        }
        return 0.85
    }

    /// Whether to downscale Retina (2x) screenshots to standard (1x) resolution.
    static var downscaleRetina: Bool {
        UserDefaults.standard.bool(forKey: "downscaleRetina")
    }

    /// Whether to embed an sRGB ICC color profile in saved images.
    static var embedColorProfile: Bool {
        let val = UserDefaults.standard.object(forKey: "embedColorProfile") as? Bool
        return val ?? true  // on by default
    }

    /// Whether to strip EXIF/metadata from saved images for privacy.
    static var stripMetadata: Bool {
        UserDefaults.standard.bool(forKey: "stripImageMetadata")
    }

    /// Maximum pixel dimension (width or height). 0 means no limit.
    static var maxDimension: Int {
        UserDefaults.standard.integer(forKey: "maxImageDimension")
    }

    /// Whether to add a drop shadow around saved images.
    static var addShadow: Bool {
        UserDefaults.standard.bool(forKey: "addImageShadow")
    }

    /// Watermark text (empty = disabled).
    static var watermarkText: String {
        UserDefaults.standard.string(forKey: "watermarkText") ?? ""
    }

    /// Watermark opacity 0.0–1.0.
    static var watermarkOpacity: CGFloat {
        let val = UserDefaults.standard.object(forKey: "watermarkOpacity") as? Double ?? 0.3
        return CGFloat(max(0.05, min(1.0, val)))
    }

    /// Whether to add a timestamp overlay on saved images.
    static var addTimestamp: Bool {
        UserDefaults.standard.bool(forKey: "addTimestampOverlay")
    }

    /// Timestamp format string (DateFormatter).
    static var timestampFormat: String {
        UserDefaults.standard.string(forKey: "timestampFormat") ?? "yyyy-MM-dd HH:mm:ss"
    }

    /// Apply timestamp overlay to top-left corner.
    static func applyTimestamp(to image: NSImage) -> NSImage {
        let formatter = DateFormatter()
        formatter.dateFormat = timestampFormat
        let text = formatter.string(from: Date())

        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1.0)

        let fontSize = max(10, min(18, image.size.width / 50))
        let bgAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.black.withAlphaComponent(0.5),
        ]
        let fgAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        let textSize = (text as NSString).size(withAttributes: fgAttrs)
        let margin: CGFloat = 8
        let bgRect = NSRect(x: margin - 4, y: image.size.height - textSize.height - margin - 2,
                            width: textSize.width + 8, height: textSize.height + 4)
        NSColor.black.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()

        let point = NSPoint(x: margin, y: image.size.height - textSize.height - margin)
        (text as NSString).draw(at: NSPoint(x: point.x + 0.5, y: point.y - 0.5), withAttributes: bgAttrs)
        (text as NSString).draw(at: point, withAttributes: fgAttrs)

        result.unlockFocus()
        return result
    }

    /// Apply text watermark to bottom-right corner.
    static func applyWatermark(to image: NSImage) -> NSImage {
        let text = watermarkText
        guard !text.isEmpty else { return image }

        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1.0)

        let fontSize = max(12, min(24, image.size.width / 40))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(watermarkOpacity),
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let margin: CGFloat = 12
        let point = NSPoint(
            x: image.size.width - textSize.width - margin,
            y: margin
        )

        // Draw text shadow for readability
        let shadowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.black.withAlphaComponent(watermarkOpacity * 0.5),
        ]
        (text as NSString).draw(at: NSPoint(x: point.x + 1, y: point.y - 1), withAttributes: shadowAttrs)
        (text as NSString).draw(at: point, withAttributes: attrs)

        result.unlockFocus()
        return result
    }

    /// Add drop shadow around an NSImage.
    static func applyDropShadow(to image: NSImage) -> NSImage {
        let shadowRadius: CGFloat = 20
        let shadowOffset: CGFloat = 8
        let padding = shadowRadius + shadowOffset
        let newSize = NSSize(
            width: image.size.width + padding * 2,
            height: image.size.height + padding * 2
        )
        let result = NSImage(size: newSize)
        result.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setShadow(
            offset: CGSize(width: 0, height: -shadowOffset),
            blur: shadowRadius,
            color: NSColor.black.withAlphaComponent(0.4).cgColor
        )
        image.draw(
            in: NSRect(x: padding, y: padding, width: image.size.width, height: image.size.height),
            from: .zero, operation: .sourceOver, fraction: 1.0
        )
        result.unlockFocus()
        return result
    }

    static var fileExtension: String {
        switch format {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .webp: return "webp"
        }
    }

    static var utType: UTType {
        switch format {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .webp: return .webP
        }
    }

    // MARK: - Shared bitmap creation

    /// Create a bitmap representation from an NSImage, optionally downscaling from Retina.
    /// This is the single conversion point — all encode paths go through here.
    private static func makeBitmap(_ image: NSImage) -> NSBitmapImageRep? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        if downscaleRetina {
            let logicalW = Int(image.size.width)
            let logicalH = Int(image.size.height)
            let pixelW = bitmap.pixelsWide
            let pixelH = bitmap.pixelsHigh

            if pixelW > logicalW && pixelH > logicalH {
                guard let cgImage = bitmap.cgImage else { return bitmap }
                let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                guard let ctx = CGContext(
                    data: nil,
                    width: logicalW, height: logicalH,
                    bitsPerComponent: 8,
                    bytesPerRow: logicalW * 4,
                    space: cs,
                    bitmapInfo: bitmapInfo
                ) else { return bitmap }
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: logicalW, height: logicalH))
                guard let downscaled = ctx.makeImage() else { return bitmap }
                return NSBitmapImageRep(cgImage: downscaled)
            }
        }

        // Apply max dimension limit if configured
        let maxDim = maxDimension
        if maxDim > 0 {
            let pw = bitmap.pixelsWide
            let ph = bitmap.pixelsHigh
            if pw > maxDim || ph > maxDim {
                let scale = CGFloat(maxDim) / CGFloat(max(pw, ph))
                let newW = Int(CGFloat(pw) * scale)
                let newH = Int(CGFloat(ph) * scale)
                guard let cgImage = bitmap.cgImage else { return bitmap }
                let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                guard let ctx = CGContext(
                    data: nil, width: newW, height: newH,
                    bitsPerComponent: 8, bytesPerRow: newW * 4,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return bitmap }
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
                if let resized = ctx.makeImage() {
                    return NSBitmapImageRep(cgImage: resized)
                }
            }
        }

        return bitmap
    }

    // MARK: - Encoding

    /// Encode an NSImage to Data in the configured format.
    static func encode(_ image: NSImage) -> Data? {
        var processedImage = addTimestamp ? applyTimestamp(to: image) : image
        processedImage = !watermarkText.isEmpty ? applyWatermark(to: processedImage) : processedImage
        processedImage = addShadow ? applyDropShadow(to: processedImage) : processedImage
        guard let bitmap = makeBitmap(processedImage) else { return nil }

        switch format {
        case .png:
            return encodePNG(bitmap: bitmap)
        case .jpeg:
            return encodeJPEG(bitmap: bitmap, quality: quality)
        case .heic:
            return encodeHEIC(bitmap: bitmap, quality: quality)
        case .webp:
            return encodeWebP(bitmap: bitmap, quality: quality)
        }
    }

    /// Encode PNG, optionally embedding sRGB profile via CGImageDestination.
    private static func encodePNG(bitmap: NSBitmapImageRep) -> Data? {
        if embedColorProfile, let cgImage = bitmap.cgImage {
            return encodeWithCGImageDestination(cgImage: cgImage, type: "public.png", lossyQuality: nil)
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Encode JPEG, optionally embedding sRGB profile via CGImageDestination.
    private static func encodeJPEG(bitmap: NSBitmapImageRep, quality: CGFloat) -> Data? {
        if embedColorProfile, let cgImage = bitmap.cgImage {
            return encodeWithCGImageDestination(cgImage: cgImage, type: "public.jpeg", lossyQuality: quality)
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Encode HEIC via CGImageDestination (NSBitmapImageRep doesn't support HEIC).
    private static func encodeHEIC(bitmap: NSBitmapImageRep, quality: CGFloat) -> Data? {
        guard let cgImage = bitmap.cgImage else { return nil }
        return encodeWithCGImageDestination(cgImage: cgImage, type: "public.heic", lossyQuality: quality)
    }

    /// Encode WebP via Swift-WebP (libwebp).
    /// Uses the CGImage RGBA path directly — the library's NSImage path has a bug
    /// (assumes RGB stride and logical size instead of pixel size).
    private static func encodeWebP(bitmap: NSBitmapImageRep, quality: CGFloat) -> Data? {
        guard let srcImage = bitmap.cgImage else { return nil }
        let w = srcImage.width
        let h = srcImage.height
        // Re-render into a known premultipliedLast RGBA context
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(srcImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let rgbaImage = ctx.makeImage() else { return nil }

        let encoder = WebPEncoder()
        let config = WebPEncoderConfig.preset(.picture, quality: Float(quality * 100))
        return try? encoder.encode(RGBA: rgbaImage, config: config)
    }

    /// Generic CGImageDestination encoder — handles sRGB profile embedding.
    private static func encodeWithCGImageDestination(cgImage: CGImage, type: String, lossyQuality: CGFloat?) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil) else { return nil }

        var properties: [String: Any] = [:]
        if let q = lossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality as String] = q
        }

        // Strip EXIF/metadata for privacy if enabled
        if stripMetadata {
            properties[kCGImagePropertyExifDictionary as String] = kCFNull
            properties[kCGImagePropertyGPSDictionary as String] = kCFNull
            properties[kCGImagePropertyIPTCDictionary as String] = kCFNull
            properties[kCGImagePropertyMakerAppleDictionary as String] = kCFNull
            properties[kCGImagePropertyTIFFDictionary as String] = kCFNull
        }

        // Embed sRGB color profile by converting the image's color space
        var imageToEncode = cgImage
        if embedColorProfile, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) {
            if let profiled = cgImage.copy(colorSpace: sRGB) {
                imageToEncode = profiled
            }
        }

        CGImageDestinationAddImage(dest, imageToEncode, properties as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: - Clipboard

    /// Copy image to pasteboard as PNG.
    /// Explicitly sets PNG data so receiving apps (browsers, editors) get
    /// a lossless PNG instead of the TIFF that NSImage.writeObjects provides.
    static func copyToClipboard(_ image: NSImage) {
        guard let bitmap = makeBitmap(image),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }
}
