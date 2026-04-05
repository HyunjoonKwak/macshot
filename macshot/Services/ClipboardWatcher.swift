import Cocoa

/// Monitors the system pasteboard for new image content.
/// When a new image is detected, calls the callback.
final class ClipboardWatcher {

    static let shared = ClipboardWatcher()

    var onNewImage: ((NSImage) -> Void)?
    private var timer: Timer?
    private var lastChangeCount: Int = 0

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "clipboardWatchEnabled")
    }

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        guard isEnabled else { return }
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Check if pasteboard contains an image (but not from our own copy)
        guard let types = pb.types,
              types.contains(.tiff) || types.contains(.png) else { return }

        // Read the image
        guard let image = NSImage(pasteboard: pb), image.size.width > 10, image.size.height > 10 else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onNewImage?(image)
        }
    }
}
