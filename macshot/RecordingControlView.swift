import Cocoa

/// Borderless window that can become key (needed to receive ESC key events).
final class RecordingControlWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// A small transparent window view that sits over the right bar during recording
/// (when the main overlay has ignoresMouseEvents = true). Uses a real ToolbarStripView
/// and forwards clicks to the overlay view's toolbar handler.
final class RecordingControlView: NSView {

    weak var overlayView: OverlayView?
    private var stripView: ToolbarStripView?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    /// Rebuild the toolbar buttons from the overlay's right button data.
    func rebuildButtons() {
        guard let ov = overlayView else { return }

        if stripView == nil {
            let strip = ToolbarStripView(orientation: .vertical)
            addSubview(strip)
            stripView = strip
        }

        stripView?.setButtons(ov.rightButtons)
        stripView?.onClick = { [weak ov] action in
            ov?.handleToolbarAction(action)
        }
        stripView?.frame.origin = .zero

        // Resize this view to match the strip
        if let size = stripView?.frame.size {
            frame.size = size
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            guard let ov = overlayView else { return }
            guard !ov.isCapturingVideo else { return }
            ov.overlayDelegate?.overlayViewDidCancel()
        }
    }
}
