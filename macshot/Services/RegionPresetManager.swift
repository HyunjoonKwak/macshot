import Cocoa

/// Manages named capture region presets stored in UserDefaults.
final class RegionPresetManager {

    static let shared = RegionPresetManager()

    struct Preset: Codable {
        let name: String
        let rect: CodableRect
        let screenFrame: CodableRect

        struct CodableRect: Codable {
            let x: Double, y: Double, w: Double, h: Double

            init(_ r: NSRect) { x = r.origin.x; y = r.origin.y; w = r.width; h = r.height }
            var nsRect: NSRect { NSRect(x: x, y: y, width: w, height: h) }
        }
    }

    private let key = "regionPresets"
    private let maxPresets = 8

    var presets: [Preset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
        return decoded
    }

    func save(name: String, rect: NSRect, screenFrame: NSRect) {
        var list = presets
        // Replace if same name exists
        list.removeAll { $0.name == name }
        list.insert(Preset(name: name, rect: .init(rect), screenFrame: .init(screenFrame)), at: 0)
        if list.count > maxPresets { list = Array(list.prefix(maxPresets)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func delete(name: String) {
        var list = presets
        list.removeAll { $0.name == name }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func deleteAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
