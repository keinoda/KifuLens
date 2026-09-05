import XCTest

final class ConfiguredEngineUITests: XCTestCase {
    @MainActor
    func testAllConfiguredEnginesCanBeSelectedAndAnalyze() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-test-local-analysis-memory", "-skip-opening-reference-startup", "-show-analysis-settings",
            "-analysis.threadCount", "1", "-analysis.hashSizeMB", "256",
            "-analysis.moveTimeSeconds", "1", "-analysis.usesInfiniteTime", "NO"
        ]
        app.launch()
        let menu = app.buttons["analysisEngineMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let choices = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "engineChoice-"))
            .allElementsBoundByIndex
        let identifiers = choices.map(\.identifier)
        XCTAssertFalse(identifiers.isEmpty)
        guard let first = identifiers.first else { return }
        app.descendants(matching: .any)[first].tap()

        // 設定から増えた選択肢を列挙し、Swiftテストにエンジン名を追加せず確認する。
        for (index, identifier) in identifiers.enumerated() {
            menu.tap()
            let choice = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(choice.waitForExistence(timeout: 3))
            let name = choice.label
            choice.tap()
            let apply = app.buttons["analysisSettingsSaveButton"]
            XCTAssertTrue(apply.isEnabled)
            apply.tap()
            XCTAssertTrue(app.alerts["解析設定を反映しました"].waitForExistence(timeout: 5))
            app.alerts["解析設定を反映しました"].buttons["閉じる"].tap()
            swipePanel(app, left: true)
            swipePanel(app, left: true)
            let subtitle = app.staticTexts["analysisEngineSubtitle"]
            XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
            XCTAssertEqual(subtitle.label, name)
            let start = app.buttons["analysisStartStopButton"]
            start.tap()
            XCTAssertTrue(app.buttons["analysisLine3"].waitForExistence(timeout: 70))
            XCTAssertTrue(app.staticTexts["analysisCompletionLabel"].waitForExistence(timeout: 30))
            let depth = app.descendants(matching: .any)["engineMetricDepth"]
            XCTAssertTrue(depth.exists)
            XCTAssertFalse(depth.label.contains("245/"))
            XCTAssertFalse(depth.label.hasSuffix("/6"))
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "設定による追加-\(identifier)"
            capture.lifetime = .keepAlways
            add(capture)
            start.tap()
            if index + 1 < identifiers.count {
                swipePanel(app, left: false)
                swipePanel(app, left: false)
            }
        }
    }

    private func swipePanel(_ app: XCUIApplication, left: Bool) {
        app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.9 : 0.1, dy: 0.86))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.1 : 0.9, dy: 0.86)))
    }
}
