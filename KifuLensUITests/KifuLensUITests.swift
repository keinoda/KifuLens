import XCTest

final class KifuLensUITests: XCTestCase {
    @MainActor
    func testFloodgatePrecedentIsSwipePageAndUsesFileImport() {
        let app = XCUIApplication()
        app.launchArguments.append("-show-precedent")
        app.launchArguments.append("-skip-opening-reference-startup")
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Floodgate前例未選択"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Floodgate前例集を開いてください"].exists
        )
        XCTAssertTrue(
            app.staticTexts["Files（Google Drive等）から選択・複数可"].exists
        )
        XCTAssertTrue(app.buttons["precedentImportButton"].exists)
        XCTAssertTrue(app.buttons["precedentDownloadButton"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPhone17のFloodgate前例"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testPrecedentDownloadShowsPublishedCatalog() {
        let app = XCUIApplication()
        app.launchArguments += ["-show-precedent", "-skip-opening-reference-startup"]
        app.launch()
        let download = app.buttons["precedentDownloadButton"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.tap()
        XCTAssertTrue(app.navigationBars["前例DBのダウンロード"].waitForExistence(timeout: 5))
        let apply = app.buttons["precedentDownloadApplyButton"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: apply)
        let requestTimeout = URLSessionConfiguration.default.timeoutIntervalForRequest
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: requestTimeout), .completed)
        XCTAssertFalse(app.staticTexts["precedentDownloadError"].exists)
        let gameCount = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "対局数, ")
        ).element
        XCTAssertEqual(gameCount.label.filter(\.isNumber), "57833")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPhone17の前例DBダウンロード"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        apply.tap()
        XCTAssertTrue(app.staticTexts["前例DBを更新しました"].waitForExistence(timeout: requestTimeout))
        XCTAssertFalse(app.staticTexts["precedentDownloadError"].exists)
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["precedentMove1"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-show-precedent"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["precedentMove1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAnalysisSettingsIsLeftmostInspectorPage() {
        let app = XCUIApplication()
        app.launchArguments.append("-show-analysis-settings")
        app.launch()

        XCTAssertTrue(
            app.staticTexts["解析設定"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["エンジン"].exists)
        XCTAssertTrue(app.staticTexts["Hash"].exists)
        XCTAssertTrue(app.staticTexts["解析時間"].exists)
        XCTAssertTrue(
            app.buttons["NAGISA v3"].exists
        )
        XCTAssertTrue(app.buttons["1"].exists)
        XCTAssertTrue(app.buttons["256 MB"].exists)
        XCTAssertTrue(app.buttons["10秒"].exists)
        let appleSignInButton =
            app.buttons["analysisSettingsAppleSignInButton"]
        XCTAssertTrue(appleSignInButton.exists)
        XCTAssertFalse(appleSignInButton.isEnabled)
        XCTAssertTrue(app.buttons["analysisSettingsSaveButton"].isEnabled)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "SE3の左端解析設定"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testAnalysisSettingsShowsAppliedConfirmationWithoutAuthentication() {
        let app = XCUIApplication()
        app.launchArguments.append("-show-analysis-settings")
        app.launch()

        let applyButton = app.buttons["analysisSettingsSaveButton"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 5))
        XCTAssertTrue(applyButton.isEnabled)

        applyButton.tap()

        XCTAssertTrue(
            app.alerts["解析設定を反映しました"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testEngineBenchmarkOpensFromAnalysisSettings() {
        let app = XCUIApplication()
        app.launchArguments.append("-show-analysis-settings")
        app.launch()

        let benchmarkButton = app.buttons["engineBenchmarkButton"]
        XCTAssertTrue(benchmarkButton.waitForExistence(timeout: 5))
        benchmarkButton.tap()

        XCTAssertTrue(
            app.otherElements["engineBenchmarkSheet"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.navigationBars["ベンチマーク"].exists)
        XCTAssertTrue(app.staticTexts["実行条件"].exists)
        XCTAssertTrue(app.staticTexts["Hash"].exists)
        XCTAssertTrue(app.staticTexts["各局面"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "各5秒")
            ).firstMatch.exists
        )
        XCTAssertTrue(app.staticTexts["保存済み結果"].exists)
        XCTAssertTrue(app.buttons["engineBenchmarkRunButton"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iPhone17のベンチマーク"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testDirectExtensionAndBranchedMoveClassification() {
        let app = XCUIApplication()
        app.launch()

        let source = app.buttons["7筋7段、先手の歩"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()

        let destination = app.buttons["7筋6段、空き"]
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        destination.tap()

        let playbackPosition = app.staticTexts["playbackPosition"]
        XCTAssertTrue(playbackPosition.waitForExistence(timeout: 3))
        XCTAssertEqual(playbackPosition.label, "1手目、全1手")

        let incorporateButton = app.buttons["incorporateExplorationButton"]
        XCTAssertFalse(incorporateButton.exists)

        let backButton = app.buttons["一手戻る"]
        XCTAssertTrue(backButton.exists)
        backButton.tap()
        XCTAssertEqual(playbackPosition.label, "0手目、全1手")

        let branchSource = app.buttons["2筋7段、先手の歩"]
        XCTAssertTrue(branchSource.waitForExistence(timeout: 3))
        branchSource.tap()
        let branchDestination = app.buttons["2筋6段、空き"]
        XCTAssertTrue(branchDestination.waitForExistence(timeout: 3))
        branchDestination.tap()

        XCTAssertTrue(incorporateButton.waitForExistence(timeout: 3))
        XCTAssertEqual(incorporateButton.label, "一時検討を棋譜に取り込む")
        incorporateButton.tap()

        XCTAssertEqual(playbackPosition.label, "1手目、全1手")
        XCTAssertFalse(incorporateButton.exists)
    }

    @MainActor
    func testThreeDigitPlaybackPositionStaysOnOneLineAndExpands() {
        let app = XCUIApplication()
        app.launch()

        let recordImportButton = app.buttons["読込"]
        XCTAssertTrue(recordImportButton.waitForExistence(timeout: 5))
        recordImportButton.tap()

        let pasteTextOption = app.buttons["テキストを貼り付け"]
        XCTAssertTrue(pasteTextOption.waitForExistence(timeout: 3))
        pasteTextOption.tap()

        let cycle = ["5i5h", "5a5b", "5h5i", "5b5a"]
        let moves = Array(repeating: cycle, count: 25)
            .flatMap { $0 }
            .joined(separator: " ")
        let recordText = """
        position sfen 4k4/9/9/9/9/9/9/9/4K4 b - 1 moves \(moves)
        """

        let pastedTextEditor = app.textViews["pastedRecordTextEditor"]
        XCTAssertTrue(pastedTextEditor.waitForExistence(timeout: 3))
        pastedTextEditor.tap()
        pastedTextEditor.typeText(recordText)

        let importButton = app.buttons["pastedRecordImportButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        importButton.tap()

        let endButton = app.buttons["末尾"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.tap()

        let playbackPosition = app.staticTexts["playbackPosition"]
        XCTAssertTrue(playbackPosition.waitForExistence(timeout: 3))
        XCTAssertEqual(playbackPosition.label, "100手目、全100手")
        XCTAssertGreaterThan(
            playbackPosition.frame.width,
            44,
            "3桁同士の手数表示は従来の固定幅より広がる必要があります"
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "3桁手数表示"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRecordRowsShowSourceSquaresWithCompactSpacing() {
        let app = XCUIApplication()
        app.launch()

        let recordImportButton = app.buttons["読込"]
        XCTAssertTrue(recordImportButton.waitForExistence(timeout: 5))
        recordImportButton.tap()

        let pasteTextOption = app.buttons["テキストを貼り付け"]
        XCTAssertTrue(pasteTextOption.waitForExistence(timeout: 3))
        pasteTextOption.tap()

        let pastedTextEditor = app.textViews["pastedRecordTextEditor"]
        XCTAssertTrue(pastedTextEditor.waitForExistence(timeout: 3))
        pastedTextEditor.tap()
        pastedTextEditor.typeText(
            "position startpos moves 7g7f 3c3d 2g2f 8c8d"
        )

        let importButton = app.buttons["pastedRecordImportButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        importButton.tap()

        let firstMove = app.buttons["recordMove1"]
        let secondMove = app.buttons["recordMove2"]
        XCTAssertTrue(firstMove.waitForExistence(timeout: 5))
        XCTAssertTrue(secondMove.exists)
        XCTAssertTrue(firstMove.label.contains("☗７六歩(77)"))
        XCTAssertTrue(secondMove.label.contains("☖３四歩(33)"))
        XCTAssertLessThanOrEqual(
            secondMove.frame.minY - firstMove.frame.minY,
            31.5
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "棋譜一覧の移動元表記と詰めた配置"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testPromotionChoiceUsesPieceImagesOnBoard() {
        let app = XCUIApplication()
        app.launch()

        let recordImportButton = app.buttons["読込"]
        XCTAssertTrue(recordImportButton.waitForExistence(timeout: 5))
        recordImportButton.tap()

        let pasteTextOption = app.buttons["テキストを貼り付け"]
        XCTAssertTrue(pasteTextOption.waitForExistence(timeout: 3))
        pasteTextOption.tap()

        let pastedTextEditor = app.textViews["pastedRecordTextEditor"]
        XCTAssertTrue(pastedTextEditor.waitForExistence(timeout: 3))
        pastedTextEditor.tap()
        pastedTextEditor.typeText(
            "4k4/9/4P4/9/9/9/9/9/4K4 b - 1"
        )

        let importButton = app.buttons["pastedRecordImportButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        importButton.tap()

        let source = app.buttons["5筋3段、先手の歩"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()

        let destination = app.buttons["5筋2段、空き"]
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        destination.tap()

        let promoteButton = app.buttons["promotionPromoteButton"]
        let declineButton = app.buttons["promotionDeclineButton"]
        XCTAssertTrue(promoteButton.waitForExistence(timeout: 3))
        XCTAssertTrue(declineButton.exists)
        XCTAssertEqual(promoteButton.label, "成る")
        XCTAssertEqual(declineButton.label, "成らない")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "駒画像による成り選択"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        promoteButton.tap()
        XCTAssertTrue(
            app.buttons["5筋2段、先手のと"]
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testImportedPlayerNamesAndBoardRotationFollowShogiHubLayout() {
        let app = XCUIApplication()
        app.launch()

        let recordImportButton = app.buttons["読込"]
        XCTAssertTrue(recordImportButton.waitForExistence(timeout: 5))
        recordImportButton.tap()
        app.buttons["テキストを貼り付け"].tap()

        let pastedTextEditor = app.textViews["pastedRecordTextEditor"]
        XCTAssertTrue(pastedTextEditor.waitForExistence(timeout: 3))
        pastedTextEditor.tap()
        pastedTextEditor.typeText(
            "V2.2\nN+Murakumo\nN-Asanagi\nPI\n+"
        )
        app.buttons["pastedRecordImportButton"].tap()

        let blackName = app.staticTexts["blackPlayerNameLabel"]
        let whiteName = app.staticTexts["whitePlayerNameLabel"]
        XCTAssertTrue(blackName.waitForExistence(timeout: 5))
        XCTAssertTrue(whiteName.exists)
        XCTAssertEqual(blackName.label, "Murakumo")
        XCTAssertEqual(whiteName.label, "Asanagi")

        let flipButton = app.buttons["boardFlipButton"]
        XCTAssertTrue(flipButton.exists)

        let originallyFlipped = blackName.frame.minY < whiteName.frame.minY
        if originallyFlipped {
            flipButton.tap()
        }

        XCTAssertLessThan(whiteName.frame.minX, blackName.frame.minX)
        XCTAssertLessThan(whiteName.frame.minY, blackName.frame.minY)

        let whiteTopLeft = whiteName.frame
        let blackBottomRight = blackName.frame
        let whiteLance = app.buttons["9筋1段、後手の香"]
        XCTAssertTrue(whiteLance.exists)
        let whiteLanceNormalFrame = whiteLance.frame

        flipButton.tap()

        XCTAssertLessThan(whiteName.frame.minX, blackName.frame.minX)
        XCTAssertLessThan(blackName.frame.minY, whiteName.frame.minY)
        XCTAssertGreaterThan(
            whiteLance.frame.minX,
            whiteLanceNormalFrame.minX
        )
        XCTAssertGreaterThan(
            whiteLance.frame.minY,
            whiteLanceNormalFrame.minY
        )
        XCTAssertEqual(whiteTopLeft.minX, whiteName.frame.minX, accuracy: 2)
        XCTAssertEqual(
            blackBottomRight.minX,
            blackName.frame.minX,
            accuracy: 2
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ShogiHub準拠の盤面反転"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        if !originallyFlipped {
            flipButton.tap()
        }
    }

    @MainActor
    func testSwipeToAnalysisAndShowsThreeNagisaCandidates() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-ui-test-local-analysis-memory",
            "-analysis.engineIdentifier", "nagisa-v3",
            "-analysis.threadCount", "1",
            "-analysis.hashSizeMB", "256",
            "-analysis.moveTimeSeconds", "10",
            "-analysis.usesInfiniteTime", "NO",
        ])
        app.launch()

        let recordHeader = app.staticTexts["panelContextPrimary"]
        guard recordHeader.waitForExistence(timeout: 5) else {
            XCTFail("棋譜パネルが表示されませんでした")
            return
        }

        let start = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.86)
        )
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1, dy: 0.86)
        )
        start.press(forDuration: 0.05, thenDragTo: end)

        guard app.staticTexts["analysisEngineSubtitle"]
            .waitForExistence(timeout: 5)
        else {
            XCTFail("横スワイプで解析パネルへ遷移できませんでした")
            return
        }
        let engineDescription = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "NAGISA v3"))
            .firstMatch
        XCTAssertTrue(
            engineDescription.waitForExistence(timeout: 5),
            "端末内解析のエンジン名がNAGISA v3ではありません"
        )
        XCTAssertFalse(
            app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", "YaneuraOu"))
                .firstMatch
                .exists,
            "端末内解析に内部エンジン名が表示されています"
        )

        let analysisButton = app.buttons["analysisStartStopButton"]
        guard analysisButton.waitForExistence(timeout: 5) else {
            XCTFail("解析開始ボタンが表示されませんでした")
            return
        }
        XCTAssertEqual(analysisButton.label, "解析開始")
        analysisButton.tap()

        let engineMoveArrow =
            app.descendants(matching: .any)["engineMoveArrow"]
        guard engineMoveArrow.waitForExistence(timeout: 70) else {
            XCTFail("解析中の最善手矢印が盤面に表示されませんでした")
            return
        }

        let arrowScreenshot = XCTAttachment(screenshot: app.screenshot())
        arrowScreenshot.name = "解析中の最善手矢印"
        arrowScreenshot.lifetime = .keepAlways
        add(arrowScreenshot)

        let thirdCandidate = app.buttons["analysisLine3"]
        guard thirdCandidate.waitForExistence(timeout: 70) else {
            XCTFail("NAGISA_V3の第3候補が表示されませんでした")
            return
        }

        let completionLabel = app.staticTexts["analysisCompletionLabel"]
        XCTAssertTrue(
            completionLabel.waitForExistence(timeout: 30),
            "10秒の思考後に解析が自動終了しませんでした"
        )
        XCTAssertTrue(completionLabel.label.contains("10秒解析完了"))
        XCTAssertEqual(analysisButton.label, "解析追従停止")
        XCTAssertTrue(engineMoveArrow.exists)

        let firstCandidate = app.buttons["analysisLine1"]
        let secondCandidate = app.buttons["analysisLine2"]
        XCTAssertTrue(firstCandidate.exists)
        XCTAssertTrue(secondCandidate.exists)
        XCTAssertTrue(thirdCandidate.exists)
        XCTAssertTrue(firstCandidate.isHittable)
        XCTAssertTrue(secondCandidate.isHittable)
        XCTAssertTrue(thirdCandidate.isHittable)
        XCTAssertFalse(app.buttons["analysisLine4"].exists)
        XCTAssertLessThan(firstCandidate.frame.minY, secondCandidate.frame.minY)
        XCTAssertLessThan(secondCandidate.frame.minY, thirdCandidate.frame.minY)
        XCTAssertLessThanOrEqual(thirdCandidate.frame.maxY, app.frame.maxY - 8)

        let metricIdentifiers = [
            "engineMetricTime",
            "engineMetricHash",
            "engineMetricDepth",
            "engineMetricNodes",
            "engineMetricNPS",
        ]
        let metricElements = metricIdentifiers.map {
            app.descendants(matching: .any)[$0]
        }
        XCTAssertTrue(metricElements.allSatisfy(\.exists))
        let metricWidths = metricElements.map(\.frame.width)
        XCTAssertLessThan(
            (metricWidths.max() ?? 0) - (metricWidths.min() ?? 0),
            2
        )
        XCTAssertLessThan(metricElements[0].frame.minX - app.frame.minX, 12)
        XCTAssertLessThan(app.frame.maxX - metricElements[4].frame.maxX, 12)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "MultiPV 3 の解析結果"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        analysisButton.tap()
        XCTAssertEqual(analysisButton.label, "解析開始")
    }

    @MainActor
    func testAnalysisDropArrowStartsAtMeasuredHandPiecePosition() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-ui-test-local-analysis-memory",
            "-analysis.engineIdentifier", "nagisa-v3",
            "-analysis.threadCount", "1",
            "-analysis.hashSizeMB", "256",
            "-analysis.moveTimeSeconds", "10",
            "-analysis.usesInfiniteTime", "NO",
        ])
        app.launch()

        let recordImportButton = app.buttons["読込"]
        XCTAssertTrue(recordImportButton.waitForExistence(timeout: 5))
        recordImportButton.tap()
        let pasteTextOption = app.buttons["テキストを貼り付け"]
        XCTAssertTrue(pasteTextOption.waitForExistence(timeout: 3))
        pasteTextOption.tap()

        let pastedTextEditor = app.textViews["pastedRecordTextEditor"]
        XCTAssertTrue(pastedTextEditor.waitForExistence(timeout: 3))
        pastedTextEditor.tap()
        pastedTextEditor.typeText(
            "position sfen "
                + "4r3k/9/9/9/9/9/9/3L1L3/3PKP3 b G 1"
        )
        let importButton = app.buttons["pastedRecordImportButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        importButton.tap()

        XCTAssertTrue(app.buttons["金1枚"].waitForExistence(timeout: 5))

        let start = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.86)
        )
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1, dy: 0.86)
        )
        start.press(forDuration: 0.05, thenDragTo: end)

        let analysisButton = app.buttons["analysisStartStopButton"]
        XCTAssertTrue(analysisButton.waitForExistence(timeout: 5))
        analysisButton.tap()

        let engineMoveArrow =
            app.descendants(matching: .any)["engineMoveArrow"]
        XCTAssertTrue(
            engineMoveArrow.waitForExistence(timeout: 70),
            "持ち駒からの最善手矢印が表示されませんでした"
        )
        let firstCandidate = app.buttons["analysisLine1"]
        XCTAssertTrue(firstCandidate.waitForExistence(timeout: 70))
        XCTAssertTrue(
            firstCandidate.label.contains("金打"),
            "合駒以外では受けられない局面で金打ちが選ばれませんでした"
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "持ち駒の実配置を始点にした最善手矢印"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        analysisButton.tap()
    }

    @MainActor
    func testSwipeToAnalysisShowsPolicyValueBeforeStartingNagisa() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["panelContextPrimary"].waitForExistence(timeout: 5)
        )

        let start = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.86)
        )
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1, dy: 0.86)
        )
        start.press(forDuration: 0.05, thenDragTo: end)

        let headerTexts = app.staticTexts.matching(
            identifier: "policyValueHeader"
        )
        XCTAssertTrue(
            headerTexts.firstMatch.waitForExistence(timeout: 10),
            "解析開始前にDL水匠の推定選択率が表示されませんでした"
        )
        let headerLabels = headerTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(headerLabels.contains("DL水匠・推定選択率"))
        XCTAssertTrue(
            headerLabels.contains { $0.hasPrefix("手番側勝率 ") }
        )

        let analysisButton = app.buttons["analysisStartStopButton"]
        XCTAssertTrue(analysisButton.exists)
        XCTAssertEqual(analysisButton.label, "解析開始")
        XCTAssertFalse(app.descendants(matching: .any)["storedAnalysisHeader"].exists)

        for rank in 1...7 {
            let candidate = app.buttons["policyValueLine\(rank)"]
            XCTAssertTrue(candidate.exists)
            XCTAssertTrue(candidate.isHittable)
            XCTAssertTrue(candidate.label.contains("%"))
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "解析開始前のDL水匠推定選択率"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let candidateList = app.scrollViews["policyValueCandidateList"]
        XCTAssertTrue(candidateList.exists)
        candidateList.swipeUp()
        let scrolledCandidates = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "policyValueLine"
            )
        ).allElementsBoundByIndex
        XCTAssertTrue(
            scrolledCandidates.contains { candidate in
                guard candidate.isHittable,
                      let rank = Int(
                          candidate.identifier
                              .replacingOccurrences(
                                  of: "policyValueLine",
                                  with: ""
                              )
                      )
                else {
                    return false
                }
                return rank > 7
            },
            "8位以下の推定選択率がスクロール表示されませんでした"
        )
    }

    @MainActor
    func testSavedAnalysisReplacesPolicyValueForCurrentPosition() {
        let app = XCUIApplication()
        app.launch()

        let recordImportButton = app.buttons["読込"]
        XCTAssertTrue(recordImportButton.waitForExistence(timeout: 5))
        recordImportButton.tap()
        app.buttons["テキストを貼り付け"].tap()

        let pastedTextEditor = app.textViews["pastedRecordTextEditor"]
        XCTAssertTrue(pastedTextEditor.waitForExistence(timeout: 3))
        pastedTextEditor.tap()
        pastedTextEditor.typeText(
            """
            手合割：平手
            手数----指手---------消費時間--
               1 ７六歩(77)
            ** Engine NAGISA Version v3.1 候補1 深さ 21/36 ノード数 962902 評価値 37 読み筋 △３四歩(33) ▲２六歩(27)
            """
        )
        app.buttons["pastedRecordImportButton"].tap()

        let forwardButton = app.buttons["一手進む"]
        XCTAssertTrue(forwardButton.waitForExistence(timeout: 5))
        forwardButton.tap()
        XCTAssertEqual(
            app.staticTexts["playbackPosition"].label,
            "1手目、全1手"
        )

        let start = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.86)
        )
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1, dy: 0.86)
        )
        start.press(forDuration: 0.05, thenDragTo: end)

        let storedHeader = app.staticTexts["storedAnalysisHeader"]
        XCTAssertTrue(
            storedHeader.waitForExistence(timeout: 5),
            "保存済み解析が解析欄に表示されませんでした"
        )
        XCTAssertEqual(storedHeader.label, "NAGISA v3.1・保存済み解析")
        XCTAssertTrue(
            app.descendants(matching: .any)["storedAnalysisLine1"].exists
        )
        XCTAssertFalse(
            app.staticTexts["policyValueHeader"].exists,
            "保存済み解析がある局面で推定選択率が表示されています"
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "保存済み解析による推定選択率の置換"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testImportsPastedCSATextAndShowsSaveAndOneShotWebCSAImport() {
        let app = XCUIApplication()
        app.launch()

        let recordImportButton = app.buttons["読込"]
        XCTAssertTrue(recordImportButton.waitForExistence(timeout: 5))
        recordImportButton.tap()

        let pasteTextOption = app.buttons["テキストを貼り付け"]
        XCTAssertTrue(pasteTextOption.waitForExistence(timeout: 3))
        pasteTextOption.tap()

        XCTAssertTrue(
            app.buttons["pasteRecordFromClipboardButton"]
                .waitForExistence(timeout: 3)
        )
        let pastedTextEditor = app.textViews["pastedRecordTextEditor"]
        XCTAssertTrue(pastedTextEditor.waitForExistence(timeout: 3))
        pastedTextEditor.tap()
        pastedTextEditor.typeText(
            "V2.2\nN+Black\nN-White\nPI\n+\n+7776FU\n-3334FU"
        )

        let importButton = app.buttons["pastedRecordImportButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        XCTAssertTrue(importButton.isEnabled)
        importButton.tap()

        let importedTitle = app.staticTexts["panelContextPrimary"]
        XCTAssertTrue(importedTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(importedTitle.label, "棋譜")

        let playbackPosition = app.staticTexts["playbackPosition"]
        XCTAssertTrue(playbackPosition.waitForExistence(timeout: 3))
        XCTAssertEqual(playbackPosition.label, "0手目、全2手")

        let forwardTen = app.buttons["10手進む"]
        let backTen = app.buttons["10手戻る"]
        XCTAssertTrue(forwardTen.exists)
        XCTAssertTrue(backTen.exists)
        forwardTen.tap()
        XCTAssertEqual(playbackPosition.label, "2手目、全2手")
        backTen.tap()
        XCTAssertEqual(playbackPosition.label, "0手目、全2手")

        let saveButton = app.buttons["保存"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()
        XCTAssertTrue(
            app.staticTexts[
                "KIF形式でKifuLens/kifへ保存します。"
                    + "一時検討も変化手順として含め、既存の同名ファイルは上書きしません。"
            ].waitForExistence(timeout: 3)
        )
        app.buttons["キャンセル"].tap()

        recordImportButton.tap()
        let webCSAOption = app.buttons["Web CSAを指定"]
        XCTAssertTrue(webCSAOption.waitForExistence(timeout: 3))
        webCSAOption.tap()

        XCTAssertTrue(
            app.textViews["webCSAURLTextEditor"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "自動更新はしません"))
                .firstMatch
                .exists
        )
        XCTAssertFalse(app.switches["urlImportAutoReloadToggle"].exists)
    }

    @MainActor
    func testOpensBundledLegalDocumentsFromCompactHeaderButton() {
        let app = XCUIApplication()
        app.launch()

        let informationButton = app.buttons["legalInformationButton"]
        XCTAssertTrue(informationButton.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(informationButton.frame.height, 32.5)
        informationButton.tap()

        XCTAssertTrue(app.navigationBars["情報"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["legalVersionLabel"].exists
        )

        let documents = [
            ("termsOfUseLink", "利用規約"),
            ("privacyPolicyLink", "プライバシーポリシー"),
            ("openSourceLicensesLink", "オープンソースライセンス"),
            ("gplVersion3Link", "GNU GPL version 3"),
        ]

        for (identifier, title) in documents {
            let link = app.buttons[identifier]
            XCTAssertTrue(
                link.waitForExistence(timeout: 3),
                "\(title)への導線が表示されません"
            )
            link.tap()

            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(
                navigationBar.waitForExistence(timeout: 3),
                "\(title)を開けません"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["legalDocumentText"]
                    .waitForExistence(timeout: 3),
                "\(title)の本文を表示できません"
            )

            let backButton = navigationBar.buttons["情報"]
            XCTAssertTrue(backButton.exists)
            backButton.tap()
        }

        app.buttons["閉じる"].tap()
        XCTAssertTrue(informationButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testFilePickersOpenInKifAndBookDirectories() {
        let app = XCUIApplication()
        app.launch()

        let recordImportButton = app.buttons["読込"]
        XCTAssertTrue(recordImportButton.waitForExistence(timeout: 5))
        recordImportButton.tap()

        let fileOption = app.buttons["ファイルから開く"]
        XCTAssertTrue(fileOption.waitForExistence(timeout: 3))
        fileOption.tap()

        let kifDirectoryButton = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "kif"))
            .firstMatch
        XCTAssertTrue(
            kifDirectoryButton.waitForExistence(timeout: 5),
            "棋譜ファイル画面がKifuLens/kifから開きませんでした"
        )
        app.buttons["Cancel"].tap()

        let pageStart = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.86)
        )
        let pageEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1, dy: 0.86)
        )
        pageStart.press(forDuration: 0.05, thenDragTo: pageEnd)
        pageStart.press(forDuration: 0.05, thenDragTo: pageEnd)

        let bookImportButton = app.buttons["定跡を開く"]
        XCTAssertTrue(bookImportButton.waitForExistence(timeout: 5))
        bookImportButton.tap()

        let bookDirectoryButton = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "book"))
            .firstMatch
        XCTAssertTrue(
            bookDirectoryButton.waitForExistence(timeout: 5),
            "定跡ファイル画面がKifuLens/bookから開きませんでした"
        )
        app.buttons["Cancel"].tap()
    }
}
