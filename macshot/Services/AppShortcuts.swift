import AppIntents

// MARK: - Capture Area Intent

@available(macOS 13.0, *)
struct CaptureAreaIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Area"
    static var description = IntentDescription("Open ScreenShot to capture a selected area of the screen.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.hyunjoonkwak.screenshot.captureArea"),
            object: nil, userInfo: nil, deliverImmediately: true
        )
        return .result()
    }
}

// MARK: - Capture Full Screen Intent

@available(macOS 13.0, *)
struct CaptureFullScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Full Screen"
    static var description = IntentDescription("Capture the entire screen with ScreenShot.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.hyunjoonkwak.screenshot.captureFullScreen"),
            object: nil, userInfo: nil, deliverImmediately: true
        )
        return .result()
    }
}

// MARK: - Capture OCR Intent

@available(macOS 13.0, *)
struct CaptureOCRIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture & Extract Text (OCR)"
    static var description = IntentDescription("Capture a screen region and extract text using OCR.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.hyunjoonkwak.screenshot.captureOCR"),
            object: nil, userInfo: nil, deliverImmediately: true
        )
        return .result()
    }
}

// MARK: - App Shortcuts Provider

@available(macOS 13.0, *)
struct ScreenShotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureAreaIntent(),
            phrases: [
                "Capture area with \(.applicationName)",
                "\(.applicationName)로 영역 캡처",
            ],
            shortTitle: "Capture Area",
            systemImageName: "crop"
        )
        AppShortcut(
            intent: CaptureFullScreenIntent(),
            phrases: [
                "Capture full screen with \(.applicationName)",
                "\(.applicationName)로 전체 화면 캡처",
            ],
            shortTitle: "Full Screen",
            systemImageName: "desktopcomputer"
        )
        AppShortcut(
            intent: CaptureOCRIntent(),
            phrases: [
                "Extract text from screen with \(.applicationName)",
                "\(.applicationName)로 텍스트 추출",
            ],
            shortTitle: "OCR Capture",
            systemImageName: "text.viewfinder"
        )
    }
}
