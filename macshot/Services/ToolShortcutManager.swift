import Foundation

/// Manages customizable single-key shortcuts for annotation tools.
/// Shortcuts are stored in UserDefaults and can be modified via Preferences.
final class ToolShortcutManager {

    static let shared = ToolShortcutManager()

    /// Default key bindings: key → ToolbarButtonAction
    static let defaultBindings: [(key: String, action: ToolbarButtonAction)] = [
        ("p", .tool(.pencil)),
        ("a", .tool(.arrow)),
        ("l", .tool(.line)),
        ("r", .tool(.rectangle)),
        ("t", .tool(.text)),
        ("m", .tool(.marker)),
        ("n", .tool(.number)),
        ("b", .tool(.pixelate)),
        ("x", .tool(.pixelate)),
        ("i", .tool(.colorSampler)),
        ("s", .tool(.select)),
        ("g", .tool(.stamp)),
        ("e", .detach),
    ]

    private var bindings: [String: ToolbarButtonAction] = [:]

    private init() {
        loadBindings()
    }

    /// Returns the action for a given key, or nil if no binding exists.
    func action(for key: String) -> ToolbarButtonAction? {
        bindings[key.lowercased()]
    }

    /// Returns the key bound to a given tool, or nil.
    func key(for targetAction: ToolbarButtonAction) -> String? {
        for (key, action) in bindings {
            if actionID(action) == actionID(targetAction) { return key }
        }
        return nil
    }

    /// Returns all current bindings as (key, action) pairs.
    func allBindings() -> [(key: String, action: ToolbarButtonAction)] {
        bindings.map { (key: $0.key, action: $0.value) }
            .sorted { $0.key < $1.key }
    }

    /// Updates a binding. Pass nil for action to remove a key.
    func setBinding(key: String, action: ToolbarButtonAction?) {
        let k = key.lowercased()
        if let action = action {
            bindings[k] = action
        } else {
            bindings.removeValue(forKey: k)
        }
        saveBindings()
    }

    /// Resets all bindings to defaults.
    func resetToDefaults() {
        bindings = [:]
        for entry in Self.defaultBindings {
            bindings[entry.key] = entry.action
        }
        saveBindings()
    }

    // MARK: - Persistence

    private func loadBindings() {
        guard let saved = UserDefaults.standard.dictionary(forKey: "toolShortcutBindings") as? [String: String] else {
            resetToDefaults()
            return
        }
        bindings = [:]
        for (key, id) in saved {
            if let action = actionFromID(id) {
                bindings[key] = action
            }
        }
    }

    private func saveBindings() {
        var dict: [String: String] = [:]
        for (key, action) in bindings {
            dict[key] = actionID(action)
        }
        UserDefaults.standard.set(dict, forKey: "toolShortcutBindings")
    }

    // MARK: - Action ID conversion

    private func actionID(_ action: ToolbarButtonAction) -> String {
        switch action {
        case .tool(let tool): return "tool.\(tool)"
        case .detach: return "detach"
        default: return "unknown"
        }
    }

    private func actionFromID(_ id: String) -> ToolbarButtonAction? {
        if id == "detach" { return .detach }
        if id.hasPrefix("tool.") {
            let toolName = String(id.dropFirst(5))
            // Map tool name strings back to AnnotationTool cases
            switch toolName {
            case "pencil": return .tool(.pencil)
            case "arrow": return .tool(.arrow)
            case "line": return .tool(.line)
            case "rectangle": return .tool(.rectangle)
            case "filledRectangle": return .tool(.filledRectangle)
            case "ellipse": return .tool(.ellipse)
            case "text": return .tool(.text)
            case "marker": return .tool(.marker)
            case "number": return .tool(.number)
            case "pixelate": return .tool(.pixelate)
            case "blur": return .tool(.blur)
            case "colorSampler": return .tool(.colorSampler)
            case "select": return .tool(.select)
            case "stamp": return .tool(.stamp)
            case "measure": return .tool(.measure)
            case "loupe": return .tool(.loupe)
            case "translateOverlay": return .tool(.translateOverlay)
            case "crop": return .tool(.crop)
            default: return nil
            }
        }
        return nil
    }
}
