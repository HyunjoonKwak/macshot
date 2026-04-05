import Cocoa

/// Manages saved annotation style presets (color, stroke width, line style, etc.)
final class AnnotationPresetManager {

    static let shared = AnnotationPresetManager()

    struct Preset: Codable {
        let name: String
        let colorHex: String
        let strokeWidth: Double
        let lineStyle: Int
        let arrowStyle: Int
        let rectFillStyle: Int
        let cornerRadius: Double
        let opacity: Double
    }

    private let key = "annotationPresets"
    private let maxPresets = 8

    var presets: [Preset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
        return decoded
    }

    func save(name: String, color: NSColor, strokeWidth: CGFloat, lineStyle: Int,
              arrowStyle: Int, rectFillStyle: Int, cornerRadius: CGFloat, opacity: CGFloat) {
        let hex = colorToHex(color)
        var list = presets
        list.removeAll { $0.name == name }
        list.insert(Preset(
            name: name, colorHex: hex, strokeWidth: Double(strokeWidth),
            lineStyle: lineStyle, arrowStyle: arrowStyle,
            rectFillStyle: rectFillStyle, cornerRadius: Double(cornerRadius),
            opacity: Double(opacity)
        ), at: 0)
        if list.count > maxPresets { list = Array(list.prefix(maxPresets)) }
        persist(list)
    }

    func delete(name: String) {
        var list = presets
        list.removeAll { $0.name == name }
        persist(list)
    }

    private func persist(_ list: [Preset]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func applyPreset(_ preset: Preset, to view: OverlayView) {
        if let color = hexToColor(preset.colorHex) {
            view.currentColor = color
        }
        view.currentLineStyle = LineStyle(rawValue: preset.lineStyle) ?? .solid
        view.currentArrowStyle = ArrowStyle(rawValue: preset.arrowStyle) ?? .single
        view.currentRectFillStyle = RectFillStyle(rawValue: preset.rectFillStyle) ?? .stroke
        view.currentRectCornerRadius = CGFloat(preset.cornerRadius)
        if let tool = view.currentTool as AnnotationTool? {
            view.setActiveStrokeWidth(CGFloat(preset.strokeWidth), for: tool)
        }
    }

    // MARK: - Color Helpers

    private func colorToHex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#FF0000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    func hexToColor(_ hex: String) -> NSColor? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        return NSColor(
            red: CGFloat((val >> 16) & 0xFF) / 255,
            green: CGFloat((val >> 8) & 0xFF) / 255,
            blue: CGFloat(val & 0xFF) / 255,
            alpha: 1.0
        )
    }
}
