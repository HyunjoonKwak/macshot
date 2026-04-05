import Cocoa
import Carbon
import UniformTypeIdentifiers
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var overlayControllers: [OverlayWindowController] = []
    private var preferencesController: PreferencesWindowController?
    private var onboardingController: PermissionOnboardingController?
    private var pinControllers: [PinWindowController] = []
    private var thumbnailControllers: [FloatingThumbnailController] = []
    private var ocrController: OCRResultController?
    private var historyMenu: NSMenu?
    private var regionsMenu: NSMenu?
    private var historyOverlayController: HistoryOverlayController?
    private var isCapturing = false
    private var delayCountdownWindow: NSWindow?
    private var delayTimer: Timer?
    private var delayEscMonitor: Any?
    private var pendingDelaySelection: NSRect = .zero
    private var uploadToastController: UploadToastController?
    private var recordingEngine: RecordingEngine?
    private var recordingOverlayController: OverlayWindowController?
    private var recordingHUDPanel: RecordingHUDPanel?
    private var recordingScreenRect: NSRect = .zero  // screen-space capture rect
    private var recordingScreen: NSScreen?
    private var mouseHighlightOverlay: MouseHighlightOverlay?
    private var selectionBorderOverlay: SelectionBorderOverlay?
    private var menuBarIconWasHidden: Bool = false  // restore after recording if user had it hidden
    private var scrollCaptureController: ScrollCaptureController?
    /// The overlay controller whose selection is being scroll-captured.
    private var scrollCaptureOverlayController: OverlayWindowController?
    private var scrollCapturePreviewPanel: ScrollCapturePreviewPanel?
    private var statusBarMenu: NSMenu?

    /// Shared capture sound — loaded once, reused everywhere.
    static let captureSound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Prevent multiple instances — if already running, activate the existing one and quit
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hyunjoonkwak.screenshot"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            // Tell the existing instance to show its icon and open Preferences
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.hyunjoonkwak.screenshot.showAndOpenPrefs"),
                object: nil, userInfo: nil, deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }

        setupMainMenu()
        setupStatusBar()
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            setMenuBarIconVisible(false)
        }
        registerHotkey()
        NotificationService.shared.requestPermission()
        setupClipboardWatcher()
        NSApp.servicesProvider = self
        // Pre-warm CoreAudio so the first capture sound doesn't stall ~1s.
        if let sound = Self.captureSound {
            sound.volume = 0
            sound.play()
            sound.stop()
            sound.volume = 1
        }

        // Listen for duplicate-launch notification to restore icon
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleShowAndOpenPrefs),
            name: .init("com.hyunjoonkwak.screenshot.showAndOpenPrefs"), object: nil
        )

        // Dismiss overlays when the user switches spaces
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )

        // Pin from history panel
        NotificationCenter.default.addObserver(
            self, selector: #selector(pinFromHistory(_:)),
            name: .init("screenshot.pinFromHistory"), object: nil
        )

        // Shortcuts.app integration — listen for intent triggers
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleShortcutCapture(_:)),
            name: .init("com.hyunjoonkwak.screenshot.captureArea"), object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleShortcutFullScreen(_:)),
            name: .init("com.hyunjoonkwak.screenshot.captureFullScreen"), object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleShortcutOCR(_:)),
            name: .init("com.hyunjoonkwak.screenshot.captureOCR"), object: nil
        )

        // Check screen recording permission. If not yet granted, show the
        // custom onboarding window instead of letting macOS throw its own dialogs.
        PermissionOnboardingController.checkPermissionSync { [weak self] granted in
            guard let self = self else { return }
            if !granted {
                self.showOnboarding()
            }
        }
    }

    private func showOnboarding() {
        // If already open, just bring it to front
        if let existing = onboardingController {
            existing.show()
            return
        }
        let oc = PermissionOnboardingController()
        oc.onPermissionGranted = { [weak self] in
            self?.onboardingController = nil
        }
        onboardingController = oc
        oc.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Re-launching ScreenShot while it's running: show the menu bar icon and open Preferences
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
            setMenuBarIconVisible(true)
        }
        openPreferences()
        return false
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        HotkeyManager.shared.unregister()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Main Menu (required when no storyboard)

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: NSLocalizedString("menu.about", comment: ""), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: NSLocalizedString("menu.quit", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyNormalStatusBarIcon()
        rebuildStatusBarMenu()
    }

    private func applyNormalStatusBarIcon() {
        if let button = statusItem.button {
            if let img = NSImage(named: "StatusBarIcon") {
                img.isTemplate = true
                img.size = NSSize(width: 22, height: 22)
                button.image = img
            } else {
                button.title = "ScreenShot"
            }
            // Use custom click handler so we can dismiss modals before showing the menu
            button.target = self
            button.action = #selector(statusBarIconClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            (button.cell as? NSButtonCell)?.highlightsBy = .pushInCellMask
        }
    }

    @objc private func statusBarIconClicked(_ sender: NSStatusBarButton) {
        // Pre-warm ScreenCaptureKit content while the user browses the menu
        ScreenCaptureManager.prewarm()

        if let modalWin = NSApp.modalWindow {
            // Modal is active — dismiss it, then show menu after it unwinds
            NSApp.stopModal()
            modalWin.close()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let menu = self.statusBarMenu else { return }
                // Show via the standard statusItem path so it looks native (no arrow)
                self.statusItem.menu = menu
                sender.performClick(nil)
                self.statusItem.menu = nil
            }
        } else {
            // No modal — show menu normally via standard NSStatusItem path
            guard let menu = statusBarMenu else { return }
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        }
    }

    private func rebuildStatusBarMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let captureAreaItem = NSMenuItem(title: NSLocalizedString("menu.capture_screen", comment: ""), action: #selector(captureScreen), keyEquivalent: "")
        captureAreaItem.target = self
        captureAreaItem.toolTip = HotkeyManager.displayString(for: .captureArea)
        captureAreaItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
        menu.addItem(captureAreaItem)

        let captureFullItem = NSMenuItem(title: NSLocalizedString("menu.capture_fullscreen", comment: ""), action: #selector(captureFullScreen), keyEquivalent: "")
        captureFullItem.target = self
        captureFullItem.toolTip = HotkeyManager.displayString(for: .captureFullScreen)
        captureFullItem.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
        menu.addItem(captureFullItem)

        let captureOCRItem = NSMenuItem(title: NSLocalizedString("menu.capture_ocr", comment: ""), action: #selector(captureOCR), keyEquivalent: "")
        captureOCRItem.target = self
        captureOCRItem.toolTip = HotkeyManager.displayString(for: .captureOCR)
        captureOCRItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
        menu.addItem(captureOCRItem)

        let quickCaptureItem = NSMenuItem(title: NSLocalizedString("menu.quick_capture", comment: ""), action: #selector(quickCapture), keyEquivalent: "")
        quickCaptureItem.target = self
        quickCaptureItem.toolTip = HotkeyManager.displayString(for: .quickCapture)
        quickCaptureItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        menu.addItem(quickCaptureItem)

        let scrollCaptureItem = NSMenuItem(title: NSLocalizedString("menu.scroll_capture", comment: ""), action: #selector(scrollCapture), keyEquivalent: "")
        scrollCaptureItem.target = self
        scrollCaptureItem.image = NSImage(systemSymbolName: "scroll", accessibilityDescription: nil)
        menu.addItem(scrollCaptureItem)

        // Capture Delay submenu
        let delayItem = NSMenuItem(title: NSLocalizedString("menu.capture_delay", comment: ""), action: nil, keyEquivalent: "")
        delayItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let delaySubmenu = NSMenu()
        delaySubmenu.autoenablesItems = false
        let currentDelay = UserDefaults.standard.integer(forKey: "captureDelaySeconds")
        for seconds in [0, 3, 5, 10, 30] {
            let title = seconds == 0 ? "None" : "\(seconds) seconds"
            let item = NSMenuItem(title: title, action: #selector(setDelaySeconds(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = seconds == currentDelay ? .on : .off
            delaySubmenu.addItem(item)
        }
        delayItem.submenu = delaySubmenu
        menu.addItem(delayItem)

        menu.addItem(NSMenuItem.separator())

        let recordAreaItem = NSMenuItem(title: NSLocalizedString("menu.record_area", comment: ""), action: #selector(recordArea), keyEquivalent: "")
        recordAreaItem.target = self
        recordAreaItem.toolTip = HotkeyManager.displayString(for: .recordArea)
        recordAreaItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        menu.addItem(recordAreaItem)

        let recordScreenItem = NSMenuItem(title: NSLocalizedString("menu.record_screen", comment: ""), action: #selector(recordFullScreen), keyEquivalent: "")
        recordScreenItem.target = self
        recordScreenItem.toolTip = HotkeyManager.displayString(for: .recordScreen)
        recordScreenItem.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: nil)
        menu.addItem(recordScreenItem)

        menu.addItem(NSMenuItem.separator())

        // Recent Captures submenu
        let historyItem = NSMenuItem(title: NSLocalizedString("menu.recent_captures", comment: ""), action: nil, keyEquivalent: "")
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let historySubmenu = NSMenu()
        historySubmenu.delegate = self
        historyItem.submenu = historySubmenu
        self.historyMenu = historySubmenu
        menu.addItem(historyItem)

        // Saved Regions submenu
        let regionsItem = NSMenuItem(title: "Saved Regions", action: nil, keyEquivalent: "")
        regionsItem.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: nil)
        let regionsSubmenu = NSMenu()
        regionsSubmenu.delegate = self
        regionsItem.submenu = regionsSubmenu
        self.regionsMenu = regionsSubmenu
        menu.addItem(regionsItem)

        let historyOverlayItem = NSMenuItem(title: NSLocalizedString("menu.show_history", comment: ""), action: #selector(showHistoryOverlay), keyEquivalent: "")
        historyOverlayItem.target = self
        historyOverlayItem.toolTip = HotkeyManager.displayString(for: .historyOverlay)
        historyOverlayItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        menu.addItem(historyOverlayItem)

        menu.addItem(NSMenuItem.separator())

        let openImageItem = NSMenuItem(title: NSLocalizedString("menu.open_image", comment: ""), action: #selector(openImageFromMenu), keyEquivalent: "")
        openImageItem.target = self
        openImageItem.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)
        menu.addItem(openImageItem)

        let pasteImageItem = NSMenuItem(title: NSLocalizedString("menu.open_clipboard", comment: ""), action: #selector(openImageFromClipboard), keyEquivalent: "")
        pasteImageItem.target = self
        pasteImageItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(pasteImageItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: NSLocalizedString("menu.preferences", comment: ""), action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        prefsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("menu.quit", comment: ""), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarMenu = menu
    }

    private func refreshMenu() {
        guard let menu = statusBarMenu, let captureItem = menu.items.first else { return }
        captureItem.toolTip = HotkeyManager.shortcutDisplayString()
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        HotkeyManager.shared.registerAll(
            captureArea: { [weak self] in
                DispatchQueue.main.async { self?.startCapture(fromMenu: false) }
            },
            captureFullScreen: { [weak self] in
                DispatchQueue.main.async { self?.captureFullScreen() }
            },
            recordArea: { [weak self] in
                DispatchQueue.main.async { self?.recordArea() }
            },
            recordScreen: { [weak self] in
                DispatchQueue.main.async { self?.recordFullScreen() }
            },
            historyOverlay: { [weak self] in
                DispatchQueue.main.async { self?.showHistoryOverlay() }
            },
            captureOCR: { [weak self] in
                DispatchQueue.main.async { self?.captureOCR() }
            },
            quickCapture: { [weak self] in
                DispatchQueue.main.async { self?.quickCapture() }
            },
            recaptureLastArea: { [weak self] in
                DispatchQueue.main.async { self?.recaptureLastArea() }
            }
        )
    }

    private var pendingRecordMode: Bool = false
    private var pendingFullScreen: Bool = false
    private var pendingFullScreenRecord: Bool = false
    private var pendingFullScreenRecordAutoStart: Bool = false
    private var pendingOCRMode: Bool = false
    private var pendingQuickCaptureMode: Bool = false
    private var pendingScrollCaptureMode: Bool = false
    private var capturedWindowTitle: String?

    // MARK: - Capture

    @objc private func captureScreen() {
        startCapture(fromMenu: true)
    }

    @objc private func captureFullScreen() {
        pendingFullScreen = true
        startCapture(fromMenu: true)
    }

    @objc private func showHistoryOverlay() {
        if let existing = historyOverlayController {
            existing.dismiss()
            historyOverlayController = nil
            return
        }
        let controller = HistoryOverlayController()
        controller.onDismiss = { [weak self] in
            self?.historyOverlayController = nil
        }
        controller.show()
        historyOverlayController = controller
    }

    @objc private func handleShortcutCapture(_ notification: Notification) {
        captureScreen()
    }
    @objc private func handleShortcutFullScreen(_ notification: Notification) {
        captureFullScreen()
    }
    @objc private func handleShortcutOCR(_ notification: Notification) {
        captureOCR()
    }

    @objc private func captureOCR() {
        pendingOCRMode = true
        startCapture(fromMenu: true)
    }

    @objc private func quickCapture() {
        pendingQuickCaptureMode = true
        startCapture(fromMenu: true)
    }

    /// Instantly re-capture the last selected area without showing the overlay.
    private func recaptureLastArea() {
        guard let rectStr = UserDefaults.standard.string(forKey: "lastSelectionRect"),
              let screenStr = UserDefaults.standard.string(forKey: "lastSelectionScreenFrame") else {
            // No saved area — fall back to normal capture
            startCapture(fromMenu: true)
            return
        }
        let savedRect = NSRectFromString(rectStr)
        let savedScreenFrame = NSRectFromString(screenStr)
        guard savedRect.width > 1, savedRect.height > 1 else {
            startCapture(fromMenu: true)
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame == savedScreenFrame }) else {
            startCapture(fromMenu: true)
            return
        }

        // Capture the screen directly
        ScreenCaptureManager.captureAllScreens { [weak self] captures in
            guard let self = self else { return }
            guard let capture = captures.first(where: { $0.screen.frame == screen.frame }) else { return }

            // Crop to the saved selection
            let scale = screen.backingScaleFactor
            let cropRect = CGRect(
                x: savedRect.origin.x * scale,
                y: (screen.frame.height - savedRect.origin.y - savedRect.height) * scale,
                width: savedRect.width * scale,
                height: savedRect.height * scale
            )
            guard let cropped = capture.image.cropping(to: cropRect) else { return }

            let image = NSImage(cgImage: cropped, size: savedRect.size)

            // Apply quick capture mode actions
            let mode = UserDefaults.standard.object(forKey: "quickCaptureMode") as? Int ?? 1
            if mode == 1 || mode == 2 {
                ImageEncoder.copyToClipboard(image)
            }
            if mode == 0 || mode == 2 {
                self.saveImageToFile(image, quickSave: true)
            }
            ScreenshotHistory.shared.add(image: image)
            self.playCopySound()
            self.showFloatingThumbnail(image: image)
        }
    }

    @objc private func scrollCapture() {
        pendingScrollCaptureMode = true
        startCapture(fromMenu: true)
    }

    @objc private func recordArea() {
        pendingRecordMode = true
        startCapture(fromMenu: true)
    }

    @objc private func recordFullScreen() {
        pendingFullScreenRecord = true
        if UserDefaults.standard.integer(forKey: "captureDelaySeconds") > 0 {
            pendingFullScreenRecordAutoStart = true
        }
        startCapture(fromMenu: true)
    }

    @objc private func setDelaySeconds(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "captureDelaySeconds")
        // Update checkmarks
        if let menu = sender.menu {
            for item in menu.items {
                item.state = item.tag == sender.tag ? .on : .off
            }
        }
    }

    private func startCapture(fromMenu: Bool = false) {
        guard !isCapturing else { return }
        // Don't allow captures while recording
        guard recordingEngine == nil else { return }
        isCapturing = true

        // Kick off SCShareableContent enumeration early — the cache will be ready
        // by the time performCapture() needs it (covers hotkey path where menu wasn't opened)
        ScreenCaptureManager.prewarm()

        // When "remember last tool" is off, clear persisted effects/beautify
        // so new OverlayView instances start clean
        let rememberTool = UserDefaults.standard.object(forKey: "rememberLastTool") as? Bool ?? true
        if !rememberTool {
            UserDefaults.standard.removeObject(forKey: "effectsPreset")
            UserDefaults.standard.removeObject(forKey: "effectsBrightness")
            UserDefaults.standard.removeObject(forKey: "effectsContrast")
            UserDefaults.standard.removeObject(forKey: "effectsSaturation")
            UserDefaults.standard.removeObject(forKey: "effectsSharpness")
            UserDefaults.standard.set(false, forKey: "beautifyEnabled")
        }

        // Grab focused window title before overlay steals focus
        capturedWindowTitle = Self.focusedWindowTitle()

        dismissOverlays()

        let delay = UserDefaults.standard.integer(forKey: "captureDelaySeconds")
        if delay > 0 {
            showPreCaptureCountdown(seconds: delay)
        } else {
            performCapture()
        }
    }

    private func showPreCaptureCountdown(seconds: Int) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 140, height: 140)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let countdownView = CountdownView(frame: NSRect(origin: .zero, size: size))
        countdownView.remaining = seconds
        window.contentView = countdownView
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        delayCountdownWindow = window

        // Listen for Escape to cancel countdown — use both local and global monitors
        // Local catches keys when macshot is active; global catches when another app has focus
        delayEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelPreCaptureCountdown()
                return nil
            }
            return event
        }

        var remaining = seconds
        delayTimer?.invalidate()
        delayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.delayTimer = nil
                self?.delayCountdownWindow?.orderOut(nil)
                self?.delayCountdownWindow = nil
                self?.removeDelayEscMonitors()
                self?.performCapture()
            } else {
                countdownView.remaining = remaining
                countdownView.needsDisplay = true
            }
        }
    }

    private func removeDelayEscMonitors() {
        if let m = delayEscMonitor { NSEvent.removeMonitor(m); delayEscMonitor = nil }
    }

    private func cancelPreCaptureCountdown() {
        delayTimer?.invalidate()
        delayTimer = nil
        delayCountdownWindow?.orderOut(nil)
        delayCountdownWindow = nil
        removeDelayEscMonitors()
        isCapturing = false
        pendingRecordMode = false
        pendingFullScreen = false
        pendingFullScreenRecord = false
        pendingFullScreenRecordAutoStart = false
        pendingOCRMode = false
        pendingQuickCaptureMode = false
        pendingScrollCaptureMode = false
    }

    private func performCapture() {
        ScreenCaptureManager.captureAllScreens { [weak self] captures in
            guard let self = self else { return }

            if captures.isEmpty {
                self.isCapturing = false
                // Permission was revoked or never granted — show onboarding instead of a generic alert
                self.showOnboarding()
                return
            }

            for capture in captures {
                let controller = OverlayWindowController(capture: capture)
                controller.overlayDelegate = self
                controller.capturedWindowTitle = self.capturedWindowTitle
                if self.pendingRecordMode {
                    controller.setAutoRecordMode()
                }
                if self.pendingOCRMode {
                    controller.setAutoOCRMode()
                }
                if self.pendingQuickCaptureMode {
                    controller.setAutoQuickSaveMode()
                }
                if self.pendingScrollCaptureMode {
                    controller.setAutoScrollCaptureMode()
                }
                controller.showOverlay()
                let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                let isMouseScreen = (capture.screen == mouseScreen) || (mouseScreen == nil && capture.screen == NSScreen.main)
                if (self.pendingFullScreen || self.pendingFullScreenRecord) && isMouseScreen {
                    controller.applyFullScreenSelection()
                }
                if self.pendingFullScreenRecord && isMouseScreen {
                    controller.enterRecordingMode()
                    if self.pendingFullScreenRecordAutoStart {
                        // Auto-start recording after a brief moment to let the overlay settle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            controller.autoStartRecording()
                        }
                    }
                }
                self.overlayControllers.append(controller)
            }

            CATransaction.flush()
            NSApp.activate(ignoringOtherApps: true)

            self.pendingRecordMode = false
            self.pendingFullScreenRecordAutoStart = false
            self.pendingOCRMode = false
            self.pendingQuickCaptureMode = false
            self.pendingScrollCaptureMode = false
            if !self.pendingFullScreen && !self.pendingFullScreenRecord {
                self.restoreLastSelectionIfNeeded(controllers: self.overlayControllers)
            }
            self.pendingFullScreen = false
            self.pendingFullScreenRecord = false
        }
    }

    /// Returns the title of the frontmost window via CGWindowList (requires Screen Recording permission).
    private static func focusedWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let name = info[kCGWindowName as String] as? String, !name.isEmpty else { continue }
            return name
        }
        return nil
    }

    private func restoreLastSelectionIfNeeded(controllers: [OverlayWindowController]) {
        guard UserDefaults.standard.bool(forKey: "rememberLastSelection") else { return }
        guard let rectStr = UserDefaults.standard.string(forKey: "lastSelectionRect"),
              let screenStr = UserDefaults.standard.string(forKey: "lastSelectionScreenFrame") else { return }
        let savedRect = NSRectFromString(rectStr)
        let savedScreenFrame = NSRectFromString(screenStr)
        guard savedRect.width > 1, savedRect.height > 1 else { return }
        // Apply to the controller whose screen matches the saved screen frame
        for controller in controllers where controller.screen.frame == savedScreenFrame {
            controller.applySelection(savedRect)
            break
        }
    }

    @objc private func handleShowAndOpenPrefs() {
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
            setMenuBarIconVisible(true)
        }
        openPreferences()
    }

    @objc private func spaceDidChange() {
        guard !overlayControllers.isEmpty else { return }
        dismissOverlays()
    }

    private func dismissOverlays() {
        autoreleasepool {
            for controller in overlayControllers {
                controller.dismiss()
            }
            overlayControllers.removeAll()
        }
        isCapturing = false
    }

    func showFloatingThumbnail(image: NSImage) {
        let enabled = UserDefaults.standard.object(forKey: "showFloatingThumbnail") as? Bool ?? true
        guard enabled else { return }

        let stacking = UserDefaults.standard.object(forKey: "thumbnailStacking") as? Bool ?? true
        if !stacking {
            // Replace mode: dismiss all existing thumbnails
            thumbnailControllers.forEach { $0.dismiss() }
            thumbnailControllers.removeAll()
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16
        let gap: CGFloat = 8

        // Compute Y: stack above any existing thumbnails
        var yOrigin = screenFrame.minY + padding
        if let topController = thumbnailControllers.last {
            let topFrame = topController.windowFrame
            yOrigin = topFrame.maxY + gap
        }

        let controller = FloatingThumbnailController(image: image)
        controller.onDismiss = { [weak self] in
            self?.thumbnailControllers.removeAll { $0 === controller }
            self?.reflowThumbnails()
        }
        controller.onCopy = { [weak self] in
            guard let self = self else { return }
            ImageEncoder.copyToClipboard(image)
            self.playCopySound()
        }
        controller.onSave = { [weak self] in
            guard let self = self else { return }
            self.saveImageToFile(image)
        }
        controller.onPin = { [weak self] in
            guard let self = self else { return }
            ScreenshotHistory.shared.add(image: image)
            self.showPin(image: image)
            self.playCopySound()
        }
        controller.onEdit = {
            DetachedEditorWindowController.open(image: image)
        }
        controller.onUpload = { [weak self] in
            guard let self = self else { return }
            ScreenshotHistory.shared.add(image: image)
            self.showUploadProgress(image: image)
        }
        controller.onCloseAll = { [weak self] in
            guard let self = self else { return }
            let all = self.thumbnailControllers
            self.thumbnailControllers.removeAll()
            for c in all { c.dismiss() }
        }
        controller.onSaveAll = { [weak self] in
            self?.saveAllThumbnailsToFolder()
        }
        thumbnailControllers.append(controller)
        controller.show(atY: yOrigin)
    }

    private func saveAllThumbnailsToFolder() {
        let images = thumbnailControllers.map { $0.image }
        guard !images.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose a folder to save \(images.count) screenshot\(images.count == 1 ? "" : "s")"
        panel.level = .floating

        panel.begin { [weak self] response in
            guard response == .OK, let dirURL = panel.url else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

            DispatchQueue.global(qos: .userInitiated).async {
                for (i, image) in images.enumerated() {
                    guard let data = ImageEncoder.encode(image) else { continue }
                    let timestamp = formatter.string(from: Date())
                    let filename = "Screenshot \(timestamp)-\(i + 1).\(ImageEncoder.fileExtension)"
                    let fileURL = dirURL.appendingPathComponent(filename)
                    try? data.write(to: fileURL)
                }
                DispatchQueue.main.async {
                    self?.playCopySound()
                    let all = self?.thumbnailControllers ?? []
                    self?.thumbnailControllers.removeAll()
                    for c in all { c.dismiss() }
                }
            }
        }
    }

    private func reflowThumbnails() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let padding: CGFloat = 16
        let gap: CGFloat = 8
        var y = screen.visibleFrame.minY + padding
        for c in thumbnailControllers {
            let h = c.windowFrame.height  // height doesn't change, only Y moves
            c.moveTo(y: y)
            y += h + gap
        }
    }

    private func playCopySound() {
        let soundEnabled = UserDefaults.standard.object(forKey: "playCopySound") as? Bool ?? true
        guard soundEnabled else { return }
        Self.captureSound?.stop()
        Self.captureSound?.play()
    }

    private func saveImageToFile(_ image: NSImage, quickSave: Bool = false) {
        guard let imageData = ImageEncoder.encode(image) else { return }

        // Quick Save: if a default directory is set, save immediately without dialog
        if quickSave, let dir = SaveDirectoryAccess.directoryHint() {
            let filename = "screenshot_\(OverlayWindowController.formattedTimestamp()).\(ImageEncoder.fileExtension)"
            let url = dir.appendingPathComponent(filename)
            do {
                try imageData.write(to: url)
                showQuickSaveToast(url: url)
            } catch {
                // Fall back to save dialog on error
                showSavePanel(imageData: imageData)
            }
            return
        }

        showSavePanel(imageData: imageData)
    }

    private func showSavePanel(imageData: Data) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [ImageEncoder.utType]
        savePanel.nameFieldStringValue = "screenshot_\(OverlayWindowController.formattedTimestamp()).\(ImageEncoder.fileExtension)"
        savePanel.directoryURL = SaveDirectoryAccess.directoryHint()
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? imageData.write(to: url)
                SaveDirectoryAccess.save(url: url.deletingLastPathComponent())
            }
        }
    }

    private func showQuickSaveToast(url: URL) {
        let toast = UploadToastController()
        uploadToastController = toast
        toast.showSuccess(link: url.lastPathComponent, deleteURL: "")
        playCopySound()
    }

    // MARK: - Upload

    func uploadImage(_ image: NSImage) {
        showUploadProgress(image: image)
    }

    @objc private func pinFromHistory(_ notification: Notification) {
        guard let image = notification.object as? NSImage else { return }
        showPin(image: image)
    }

    func showPin(image: NSImage) {
        let pin = PinWindowController(image: image)
        pin.delegate = self
        pin.show()
        pinControllers.append(pin)
    }

    private func showUploadProgress(image: NSImage) {
        uploadToastController?.dismiss()
        let toast = UploadToastController()
        uploadToastController = toast
        toast.onDismiss = { [weak self] in
            self?.uploadToastController = nil
        }
        toast.show(status: "Uploading...")

        let provider = UserDefaults.standard.string(forKey: "uploadProvider") ?? "imgbb"

        if provider == "gdrive" && !GoogleDriveUploader.shared.isSignedIn {
            toast.showError(message: "Google Drive not signed in")
            return
        }

        if provider == "s3" && !S3Uploader.shared.isConfigured {
            toast.showError(message: "S3 not configured — check Preferences")
            return
        }

        if provider == "webhook" && !WebhookUploader.shared.isConfigured {
            toast.showError(message: "Webhook not configured — check Preferences")
            return
        }

        if provider == "webhook" {
            WebhookUploader.shared.onProgress = { fraction in
                toast.updateProgress(fraction)
            }
            WebhookUploader.shared.uploadImage(image) { result in
                switch result {
                case .success(let link):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link, forType: .string)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else if provider == "gdrive" {
            GoogleDriveUploader.shared.uploadImage(image) { result in
                switch result {
                case .success(let link):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link, forType: .string)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else if provider == "s3" {
            S3Uploader.shared.onProgress = { fraction in
                toast.updateProgress(fraction)
            }
            S3Uploader.shared.uploadImage(image) { result in
                switch result {
                case .success(let link):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link, forType: .string)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else {
            ImageUploader.upload(image: image) { result in
                switch result {
                case .success(let uploadResult):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(uploadResult.link, forType: .string)

                    var uploads = UserDefaults.standard.array(forKey: "imgbbUploads") as? [[String: String]] ?? []
                    uploads.append([
                        "deleteURL": uploadResult.deleteURL,
                        "link": uploadResult.link,
                    ])
                    UserDefaults.standard.set(uploads, forKey: "imgbbUploads")

                    toast.showSuccess(link: uploadResult.link, deleteURL: uploadResult.deleteURL)
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Open Image

    @objc private func openImageFromMenu() {
        openImageWithPanel()
    }

    @objc private func openImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard), image.isValid,
              image.size.width > 0, image.size.height > 0 else {
            let alert = NSAlert()
            alert.messageText = "No Image on Clipboard"
            alert.informativeText = "Copy an image to the clipboard first, then try again."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        DetachedEditorWindowController.open(image: image)
    }

    private func openImageWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic, .webP, .image]
        panel.message = NSLocalizedString("panel.choose_image", comment: "")

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                self.openImageFile(url: url)
            }
        }
    }

    private func openImageFile(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        // Use the filename (without extension) for the editor window title
        DetachedEditorWindowController.open(image: image)
    }

    /// Handle files opened via Finder "Open With", drag-to-dock, or command line.
    func application(_ application: NSApplication, open urls: [URL]) {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "heic", "heif", "webp", "icns"]
        for url in urls {
            // Handle screenshot:// URL scheme
            if url.scheme == "screenshot" {
                handleURLScheme(url)
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            openImageFile(url: url)
        }
    }

    private func handleURLScheme(_ url: URL) {
        let action = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch action {
        case "capture", "area":
            captureScreen()
        case "fullscreen", "full":
            captureFullScreen()
        case "ocr", "text":
            captureOCR()
        case "quick":
            quickCapture()
        case "record":
            recordArea()
        case "history":
            showHistoryOverlay()
        case "preferences", "settings":
            openPreferences()
        case "recapture":
            recaptureLastArea()
        default:
            captureScreen()
        }
    }

    // MARK: - Preferences

    @objc private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
            preferencesController?.onHotkeyChanged = { [weak self] in
                self?.registerHotkey()
                self?.refreshMenu()
            }
        }
        preferencesController?.showWindow()
    }

    // MARK: - Clipboard Watcher

    private func setupClipboardWatcher() {
        ClipboardWatcher.shared.onNewImage = { [weak self] image in
            guard ClipboardWatcher.shared.isEnabled else { return }
            // Show a notification offering to open the image in editor
            let content = UNMutableNotificationContent()
            content.title = "New image in clipboard"
            content.body = "Click to open in ScreenShot editor"
            content.sound = nil
            content.categoryIdentifier = "clipboardImage"
            let request = UNNotificationRequest(identifier: "clipboard-\(UUID().uuidString)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            // Store the image for when user clicks the notification
            self?.clipboardWatchImage = image
        }
        ClipboardWatcher.shared.start()
    }

    private var clipboardWatchImage: NSImage?

    // MARK: - Saved Regions

    private func buildRegionsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let presets = RegionPresetManager.shared.presets
        if presets.isEmpty {
            let empty = NSMenuItem(title: "No saved regions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (i, preset) in presets.enumerated() {
                let w = Int(preset.rect.nsRect.width)
                let h = Int(preset.rect.nsRect.height)
                let title = "\(preset.name)  (\(w)×\(h))"
                let item = NSMenuItem(title: title, action: #selector(loadRegionPreset(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear All", action: #selector(clearAllRegionPresets), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }
        menu.addItem(NSMenuItem.separator())
        let saveItem = NSMenuItem(title: "Save Current Region...", action: #selector(saveCurrentRegion), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)
    }

    @objc private func loadRegionPreset(_ sender: NSMenuItem) {
        let presets = RegionPresetManager.shared.presets
        guard sender.tag >= 0, sender.tag < presets.count else { return }
        let preset = presets[sender.tag]
        UserDefaults.standard.set(NSStringFromRect(preset.rect.nsRect), forKey: "lastSelectionRect")
        UserDefaults.standard.set(NSStringFromRect(preset.screenFrame.nsRect), forKey: "lastSelectionScreenFrame")
        UserDefaults.standard.set(true, forKey: "rememberLastSelection")
        startCapture(fromMenu: true)
    }

    @objc private func saveCurrentRegion() {
        guard let rectStr = UserDefaults.standard.string(forKey: "lastSelectionRect"),
              let screenStr = UserDefaults.standard.string(forKey: "lastSelectionScreenFrame") else {
            let alert = NSAlert()
            alert.messageText = "No region to save"
            alert.informativeText = "Capture a region first, then save it as a preset."
            alert.runModal()
            return
        }
        let rect = NSRectFromString(rectStr)
        let screenFrame = NSRectFromString(screenStr)
        guard rect.width > 1, rect.height > 1 else { return }

        let alert = NSAlert()
        alert.messageText = "Save Region Preset"
        alert.informativeText = "Enter a name for this \(Int(rect.width))×\(Int(rect.height)) region:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = "Region \(RegionPresetManager.shared.presets.count + 1)"
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = input.stringValue.isEmpty ? "Untitled" : input.stringValue
            RegionPresetManager.shared.save(name: name, rect: rect, screenFrame: screenFrame)
        }
    }

    @objc private func clearAllRegionPresets() {
        RegionPresetManager.shared.deleteAll()
    }

    // MARK: - Services

    /// Handle "Open in ScreenShot" from Finder Services menu.
    @objc func openImageFromService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"],
        ]) as? [URL] else { return }

        for url in urls {
            openImageFile(url: url)
        }
    }

    // MARK: - Quit

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - OverlayWindowControllerDelegate

extension AppDelegate: OverlayWindowControllerDelegate {
    func overlayDidCancel(_ controller: OverlayWindowController) {
        // If the user cancels while in recording setup (before capture started),
        // just dismiss. If recording is actively capturing, stop it.
        if controller === recordingOverlayController, let engine = recordingEngine {
            engine.stopRecording()
            // stopRecordingUI() will be called by onCompletion callback
        }
        dismissOverlays()

        // Give focus back to the previously active app on cancel.
        // NSApp.hide deactivates macshot, letting macOS activate the next app in the stack.
        // Check inside the async block so windows created right after cancel (e.g. editor) are detected.
        if recordingEngine == nil {
            DispatchQueue.main.async {
                let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
                if !hasVisibleWindows {
                    NSApp.hide(nil)
                }
            }
        }
    }

    func overlayDidConfirm(_ controller: OverlayWindowController, capturedImage: NSImage?) {
        dismissOverlays()
        if let image = capturedImage {
            ScreenshotHistory.shared.add(image: image)
            showFloatingThumbnail(image: image)
            NotificationService.shared.notifyCaptured()
        }
    }

    private func stitchCrossScreenCapture(primary: OverlayWindowController, others: [OverlayWindowController]) -> NSImage? {
        let primaryOrigin = primary.screen.frame.origin
        let primarySelRect = primary.selectionRect
        // Global selection rect
        let globalRect = NSRect(x: primarySelRect.origin.x + primaryOrigin.x,
                                y: primarySelRect.origin.y + primaryOrigin.y,
                                width: primarySelRect.width, height: primarySelRect.height)

        // Determine scale from primary screen
        let scale: CGFloat
        if let screenshot = primary.screenshotImage,
           let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            scale = CGFloat(cg.width) / screenshot.size.width
        } else {
            scale = primary.screen.backingScaleFactor
        }

        let pixelW = Int(globalRect.width * scale)
        let pixelH = Int(globalRect.height * scale)
        // Use the source image's color space to avoid expensive conversion
        let cs: CGColorSpace
        if let screenshot = primary.screenshotImage,
           let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let srcCS = cg.colorSpace {
            cs = srcCS
        } else {
            cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }
        guard let cgCtx = CGContext(data: nil, width: pixelW, height: pixelH,
                                     bitsPerComponent: 8, bytesPerRow: pixelW * 4,
                                     space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        cgCtx.scaleBy(x: scale, y: scale)

        // Draw each screen's contribution
        let allControllers = [primary] + others
        for controller in allControllers {
            guard let screenshot = controller.screenshotImage else { continue }
            let screenFrame = controller.screen.frame
            // Where this screen sits relative to the global selection rect
            let drawX = screenFrame.origin.x - globalRect.origin.x
            let drawY = screenFrame.origin.y - globalRect.origin.y
            let drawRect = NSRect(x: drawX, y: drawY, width: screenFrame.width, height: screenFrame.height)

            cgCtx.saveGState()
            // Clip to only the portion within our output bounds
            cgCtx.clip(to: CGRect(x: 0, y: 0, width: globalRect.width, height: globalRect.height))
            let nsContext = NSGraphicsContext(cgContext: cgCtx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext
            screenshot.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            cgCtx.restoreGState()
        }

        guard let cgImage = cgCtx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: globalRect.size)
    }

    func overlayDidRequestPin(_ controller: OverlayWindowController, image: NSImage) {
        ScreenshotHistory.shared.add(image: image)
        dismissOverlays()
        let pin = PinWindowController(image: image)
        pin.delegate = self
        pin.show()
        pinControllers.append(pin)
    }

    func overlayDidRequestOCR(_ controller: OverlayWindowController, text: String, image: NSImage?) {
        dismissOverlays()

        // OCR action: 0 = window + copy (default), 1 = window only, 2 = copy only
        let ocrAction = UserDefaults.standard.integer(forKey: "ocrAction")
        let shouldCopy = ocrAction == 0 || ocrAction == 2
        let shouldShowWindow = ocrAction == 0 || ocrAction == 1

        if shouldCopy && !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        if shouldShowWindow {
            ocrController?.close()
            let ocr = OCRResultController(text: text, image: image)
            ocrController = ocr
            ocr.show()
        }
    }

    func overlayDidRequestUpload(_ controller: OverlayWindowController, image: NSImage) {
        ScreenshotHistory.shared.add(image: image)
        dismissOverlays()
        showUploadProgress(image: image)
    }

    func overlayDidRequestStartRecording(_ controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {
        recordingScreenRect = rect
        recordingScreen = screen

        // Capture session overrides before dismissing overlays (which destroys the overlay view)
        let formatOverride = controller.sessionRecordingFormat
        let fpsOverride = controller.sessionRecordingFPS
        let onStopOverride = controller.sessionRecordingOnStop

        let engine = RecordingEngine()
        engine.onProgress = { [weak self] seconds in
            self?.updateRecordingHUD(seconds: seconds)
        }
        engine.onCompletion = { [weak self] url, error in
            guard let self = self else { return }
            self.stopRecordingUI()

            if let url = url {
                // Add GIF recordings to screenshot history
                if url.pathExtension.lowercased() == "gif" {
                    ScreenshotHistory.shared.addRecording(url: url)
                }
                let onStop = onStopOverride ?? UserDefaults.standard.string(forKey: "recordingOnStop") ?? "editor"
                switch onStop {
                case "finder":
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                case "clipboard":
                    self.copyRecordingToClipboard(url: url)
                default:
                    VideoEditorWindowController.open(url: url)
                }
            } else if let error = error {
                #if DEBUG
                print("Recording failed: \(error.localizedDescription)")
                #endif
            }
        }
        recordingEngine = engine
        recordingOverlayController = controller

        // Dismiss overlays — recording doesn't need them anymore
        dismissOverlays()

        // Show selection border so user knows what area is being captured
        let border = SelectionBorderOverlay(screen: screen)
        border.setSelectionRect(rect)
        border.orderFront(nil)
        selectionBorderOverlay = border

        // Show the floating timer HUD
        let hud = RecordingHUDPanel()
        hud.update(elapsedSeconds: 0)
        hud.positionOnScreen(relativeTo: rect, screen: screen)
        hud.onStopRecording = { [weak self] in
            self?.stopRecording()
        }
        hud.orderFront(nil)
        recordingHUDPanel = hud

        // Start mouse highlight overlay if enabled
        if UserDefaults.standard.bool(forKey: "recordMouseHighlight") {
            let overlay = MouseHighlightOverlay(screen: screen)
            overlay.orderFront(nil)
            overlay.startMonitoring()
            mouseHighlightOverlay = overlay
        }

        // Turn menu bar icon into a stop button (ensure it's visible even if user hid it)
        enterRecordingMenuBarMode()

        // Start recording
        engine.startRecording(rect: rect, screen: screen, formatOverride: formatOverride, fpsOverride: fpsOverride)
    }

    func overlayDidRequestStopRecording(_ controller: OverlayWindowController) {
        if let engine = recordingEngine {
            engine.stopRecording()
        } else {
            // Recording mode was entered but capture never started — just dismiss
            dismissOverlays()
        }
    }

    // MARK: - Recording UI

    @objc private func stopRecording() {
        guard let engine = recordingEngine else { return }
        recordingHUDPanel?.showEncoding()
        engine.stopRecording()
    }

    private func updateRecordingHUD(seconds: Int) {
        recordingHUDPanel?.update(elapsedSeconds: seconds)
        if let screen = recordingScreen {
            recordingHUDPanel?.positionOnScreen(relativeTo: recordingScreenRect, screen: screen)
        }
    }

    private func enterRecordingMenuBarMode() {
        menuBarIconWasHidden = UserDefaults.standard.bool(forKey: "hideMenuBarIcon")
        if menuBarIconWasHidden {
            setMenuBarIconVisible(true)
        }
        // Replace menu with a single stop action, change icon to stop symbol
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop Recording")
            button.image?.isTemplate = true
            button.image?.size = NSSize(width: 22, height: 22)
        }
        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(stopRecording)
    }

    private func exitRecordingMenuBarMode() {
        applyNormalStatusBarIcon()
        rebuildStatusBarMenu()

        // Hide icon again if user had it hidden before recording
        if menuBarIconWasHidden {
            setMenuBarIconVisible(false)
            menuBarIconWasHidden = false
        }
    }

    private func copyRecordingToClipboard(url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let ext = url.pathExtension.lowercased()
        if ext == "gif", let data = try? Data(contentsOf: url) {
            // Write raw GIF data so apps can render the animation inline
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
            // Also add file URL for Finder compatibility
            item.setString(url.absoluteString, forType: .fileURL)
            pasteboard.writeObjects([item])
        } else {
            // MP4: write file URL (apps like Slack/Discord accept file drops)
            pasteboard.writeObjects([url as NSURL])
        }
        playCopySound()
    }

    private func stopRecordingUI() {
        recordingHUDPanel?.close()
        recordingHUDPanel = nil
        selectionBorderOverlay?.close()
        selectionBorderOverlay = nil
        mouseHighlightOverlay?.stopMonitoring()
        mouseHighlightOverlay?.close()
        mouseHighlightOverlay = nil
        recordingEngine = nil
        recordingOverlayController = nil
        recordingScreenRect = .zero
        recordingScreen = nil
        exitRecordingMenuBarMode()
    }

    func overlayDidRequestScrollCapture(_ controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {
        scrollCaptureOverlayController = controller

        let scc = ScrollCaptureController(captureRect: rect, screen: screen)
        scc.excludedWindowIDs = overlayControllers.map { $0.windowNumber }
        scrollCaptureController = scc

        // Read max height for the overlay HUD progress bar
        let maxH = UserDefaults.standard.object(forKey: "scrollMaxHeight") as? Int ?? 30000

        // Tell the triggering overlay to enter scroll capture mode
        controller.setScrollCaptureState(isActive: true, maxHeight: maxH)

        // Create live preview panel if there's space beside the capture region
        let overlayLevel = 257  // matches overlay window level
        if let previewPanel = ScrollCapturePreviewPanel(captureRect: rect, screen: screen, overlayLevel: overlayLevel) {
            previewPanel.orderFront(nil)
            scrollCapturePreviewPanel = previewPanel
        }

        scc.onStripAdded = { [weak self, weak controller] count in
            guard let self = self, let scc = self.scrollCaptureController else { return }
            controller?.updateScrollCaptureProgress(
                stripCount: count, pixelSize: scc.stitchedPixelSize,
                autoScrolling: scc.autoScrollActive)
        }
        scc.onPreviewUpdated = { [weak self] image in
            self?.scrollCapturePreviewPanel?.updatePreview(image: image)
        }
        scc.onAutoScrollStarted = { [weak self, weak controller] in
            guard let self = self, let scc = self.scrollCaptureController else { return }
            controller?.updateScrollCaptureProgress(
                stripCount: scc.stripCount, pixelSize: scc.stitchedPixelSize,
                autoScrolling: true)
        }
        scc.onSessionDone = { [weak self] finalImage in
            self?.handleScrollCaptureCompleted(finalImage: finalImage)
        }

        Task { await scc.startSession() }
    }

    func overlayDidRequestStopScrollCapture(_ controller: OverlayWindowController) {
        scrollCaptureController?.stopSession()
        // onSessionDone fires asynchronously via handleScrollCaptureCompleted
    }

    func overlayDidRequestToggleAutoScroll(_ controller: OverlayWindowController) {
        guard let scc = scrollCaptureController else { return }

        // If turning on, check Accessibility permission first
        if !scc.autoScrollActive {
            if !AXIsProcessTrusted() {
                // Cancel session without delivering a result, then dismiss overlays
                scc.cancelSession()
                scrollCaptureController = nil
                scrollCapturePreviewPanel?.close()
                scrollCapturePreviewPanel = nil
                scrollCaptureOverlayController?.setScrollCaptureState(isActive: false)
                scrollCaptureOverlayController = nil
                dismissOverlays()

                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                AXIsProcessTrustedWithOptions(opts)
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("alert.accessibility_required", comment: "")
                alert.informativeText = NSLocalizedString("alert.accessibility_body", comment: "")
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                return
            }
        }

        scc.toggleAutoScroll()
        let autoScrolling = scc.isActive && scc.autoScrollActive
        controller.updateScrollCaptureProgress(
            stripCount: scc.stripCount, pixelSize: scc.stitchedPixelSize,
            autoScrolling: autoScrolling)
    }

    func overlayDidBeginSelection(_ controller: OverlayWindowController) {
        for other in overlayControllers where other !== controller {
            other.clearSelection()
            other.setRemoteSelection(.zero)
        }
    }

    func overlayDidChangeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {
        for other in overlayControllers where other !== controller {
            let otherOrigin = other.screen.frame.origin
            let localRect = NSRect(x: globalRect.origin.x - otherOrigin.x,
                                   y: globalRect.origin.y - otherOrigin.y,
                                   width: globalRect.width, height: globalRect.height)
            let clipped = localRect.intersection(NSRect(origin: .zero, size: other.screen.frame.size))
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func overlayDidRemoteResizeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {
        // Update the primary screen's actual selection
        guard let primary = overlayControllers.first(where: { $0 !== controller && $0.selectionRect.width >= 1 }) else { return }
        let primaryOrigin = primary.screen.frame.origin
        let primaryLocal = NSRect(x: globalRect.origin.x - primaryOrigin.x,
                                  y: globalRect.origin.y - primaryOrigin.y,
                                  width: globalRect.width, height: globalRect.height)
        primary.applySelection(primaryLocal)

        // Update other secondary screens (not the caller — it manages its own remoteSelectionRect during drag)
        for other in overlayControllers where other !== controller && other !== primary {
            let otherOrigin = other.screen.frame.origin
            let localRect = NSRect(x: globalRect.origin.x - otherOrigin.x,
                                   y: globalRect.origin.y - otherOrigin.y,
                                   width: globalRect.width, height: globalRect.height)
            let clipped = localRect.intersection(NSRect(origin: .zero, size: other.screen.frame.size))
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func overlayDidFinishRemoteResize(_ controller: OverlayWindowController, globalRect: NSRect) {
        // Final sync after remote resize — update primary, re-sync ALL secondaries, transfer focus
        guard let primary = overlayControllers.first(where: { $0 !== controller && $0.selectionRect.width >= 1 }) else { return }
        let primaryOrigin = primary.screen.frame.origin
        let primaryLocal = NSRect(x: globalRect.origin.x - primaryOrigin.x,
                                  y: globalRect.origin.y - primaryOrigin.y,
                                  width: globalRect.width, height: globalRect.height)
        primary.applySelection(primaryLocal)
        primary.makeKey()

        // Re-sync ALL secondary screens (including the caller) from the primary's authoritative rect
        let primarySel = primary.selectionRect
        let primaryGlobal = NSRect(x: primarySel.origin.x + primaryOrigin.x,
                                   y: primarySel.origin.y + primaryOrigin.y,
                                   width: primarySel.width, height: primarySel.height)
        for other in overlayControllers where other !== primary {
            let otherOrigin = other.screen.frame.origin
            let localRect = NSRect(x: primaryGlobal.origin.x - otherOrigin.x,
                                   y: primaryGlobal.origin.y - otherOrigin.y,
                                   width: primaryGlobal.width, height: primaryGlobal.height)
            let clipped = localRect.intersection(NSRect(origin: .zero, size: other.screen.frame.size))
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func overlayCrossScreenImage(_ controller: OverlayWindowController) -> NSImage? {
        let others = overlayControllers.filter { $0 !== controller && $0.remoteSelectionRect.width >= 1 && $0.remoteSelectionRect.height >= 1 }
        guard !others.isEmpty else { return nil }
        return stitchCrossScreenCapture(primary: controller, others: others)
    }

    private func handleScrollCaptureCompleted(finalImage: NSImage?) {
        scrollCapturePreviewPanel?.close()
        scrollCapturePreviewPanel = nil
        scrollCaptureOverlayController?.setScrollCaptureState(isActive: false)
        scrollCaptureOverlayController = nil
        scrollCaptureController = nil

        dismissOverlays()

        guard let image = finalImage else { return }

        ScreenshotHistory.shared.add(image: image)
        // quickCaptureMode: 0=save, 1=copy, 2=both
        let mode = UserDefaults.standard.object(forKey: "quickCaptureMode") as? Int ?? 1
        if mode == 1 || mode == 2 {
            ImageEncoder.copyToClipboard(image)
        }
        if mode == 0 || mode == 2 {
            saveImageToFile(image, quickSave: true)
        }
        playCopySound()
        showFloatingThumbnail(image: image)
    }

    private func startDelayCountdown(seconds: Int) {
        // Create a floating countdown window centered on screen
        let size = NSSize(width: 120, height: 120)
        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let countdownView = CountdownView(frame: NSRect(origin: .zero, size: size))
        countdownView.remaining = seconds
        window.contentView = countdownView
        window.makeKeyAndOrderFront(nil)
        delayCountdownWindow = window

        var remaining = seconds
        delayTimer?.invalidate()
        delayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.delayTimer = nil
                self?.delayCountdownWindow?.orderOut(nil)
                self?.delayCountdownWindow = nil
                self?.performDelayedCapture()
            } else {
                countdownView.remaining = remaining
                countdownView.needsDisplay = true
            }
        }
    }

    private func performDelayedCapture() {
        let savedRect = pendingDelaySelection
        isCapturing = true

        ScreenCaptureManager.captureAllScreens { [weak self] captures in
            guard let self = self else { return }

            if captures.isEmpty {
                self.isCapturing = false
                return
            }

            NSApp.activate(ignoringOtherApps: true)

            for capture in captures {
                let controller = OverlayWindowController(capture: capture)
                controller.overlayDelegate = self
                controller.showOverlay()
                // Restore the selection region
                controller.applySelection(savedRect)
                self.overlayControllers.append(controller)
            }
        }
    }
}

// MARK: - PinWindowControllerDelegate

extension AppDelegate: PinWindowControllerDelegate {
    func pinWindowDidClose(_ controller: PinWindowController) {
        pinControllers.removeAll { $0 === controller }
    }
}

// MARK: - NSMenuDelegate (Recent Captures)

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == regionsMenu {
            buildRegionsMenu(menu)
            return
        }
        // Only rebuild the history submenu, not the main status bar menu
        guard menu == historyMenu else { return }

        menu.removeAllItems()

        let entries = ScreenshotHistory.shared.entries
        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent captures", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for (i, entry) in entries.enumerated() {
            let title = "\(entry.pixelWidth) \u{00D7} \(entry.pixelHeight)  —  \(entry.timeAgoString)"
            let item = NSMenuItem(title: title, action: #selector(copyHistoryEntry(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.image = ScreenshotHistory.shared.loadThumbnail(for: entry)
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        clearItem.tag = 9000
        menu.addItem(clearItem)
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        let index = sender.tag
        ScreenshotHistory.shared.copyEntry(at: index)

        // Play copy sound
        let soundEnabled = UserDefaults.standard.object(forKey: "playCopySound") as? Bool ?? true
        if soundEnabled {
            Self.captureSound?.stop()
            Self.captureSound?.play()
        }
    }

    @objc private func clearHistory() {
        ScreenshotHistory.shared.clear()
    }
}
