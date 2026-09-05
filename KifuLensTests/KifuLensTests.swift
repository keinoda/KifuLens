import CryptoKit
import Compression
import Darwin
import Foundation
import SwiftShogi
import UIKit
import XCTest
@testable import KifuLens

final class KifuLensTests: XCTestCase {
    func testNativeSearchAndPolicyShareOneEngineImage() throws {
        let handle = try XCTUnwrap(dlopen(nil, RTLD_NOW))
        defer { dlclose(handle) }
        let search = try XCTUnwrap(dlsym(handle, "kifulens_engine_start"))
        let policy = try XCTUnwrap(dlsym(handle, "kifulens_native_policy_value"))
        var searchImage = Dl_info()
        var policyImage = Dl_info()
        XCTAssertNotEqual(dladdr(search, &searchImage), 0)
        XCTAssertNotEqual(dladdr(policy, &policyImage), 0)
        // 局面キーの二重化による探索失敗の再発を防ぐ。
        XCTAssertEqual(searchImage.dli_fbase, policyImage.dli_fbase)
    }

    func testLegalDocumentsAreBundledAndReadable() throws {
        let store = LegalDocumentStore()
        let expectedText = [
            LegalDocument.termsOfUse: "GPL version 3",
            LegalDocument.privacyPolicy: "Web CSA",
            LegalDocument.openSourceLicenses: "NAGISA_V3 v3.1",
            LegalDocument.gplVersion3: "GNU GENERAL PUBLIC LICENSE",
        ]

        for document in LegalDocument.allCases {
            let text = try store.text(for: document)
            XCTAssertFalse(text.isEmpty, "\(document.title)が空です")
            XCTAssertTrue(
                text.contains(try XCTUnwrap(expectedText[document])),
                "\(document.title)の内容が想定と異なります"
            )
        }

        let terms = try store.text(for: .termsOfUse)
        let privacyPolicy = try store.text(for: .privacyPolicy)
        let openSourceLicenses = try store.text(for: .openSourceLicenses)
        let normalizedTerms = terms
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        let normalizedPrivacyPolicy = privacyPolicy
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        XCTAssertTrue(normalizedTerms.contains("複製、改変、再配布等"))
        XCTAssertTrue(normalizedTerms.contains("当該ライセンスが優先します"))
        XCTAssertTrue(normalizedTerms.contains("駒画像"))
        XCTAssertTrue(
            normalizedTerms.contains("オープンソースライセンスの対象ではありません")
        )
        XCTAssertTrue(normalizedPrivacyPolicy.contains("TestFlight"))
        XCTAssertTrue(
            normalizedPrivacyPolicy.contains("バックアップの対象から除外")
        )
        XCTAssertTrue(openSourceLicenses.contains("新ペタショック定跡 233万局面"))
        XCTAssertTrue(openSourceLicenses.contains("実測局面数は2,252,118"))
        XCTAssertTrue(
            openSourceLicenses.contains(
                "https://github.com/keinoda/YaneuraOu/tree/nagisa_v3"
            )
        )
        XCTAssertFalse(openSourceLicenses.contains("YaneuraOu-private"))
        XCTAssertTrue(
            openSourceLicenses.contains(
                "7e7088f7287c6bf4044af665dab62d1c2f0a0fa0fe44464695910729cbc073c4"
            )
        )
    }

    func testLegalMarkdownKeepsHeadingsParagraphsAndListsSeparate() {
        let blocks = LegalMarkdownParser.blocks(
            from: """
            # タイトル

            ## 見出し

            1行目
            2行目

            - 項目

            > 引用
            """
        )

        XCTAssertEqual(
            blocks.map(\.style),
            [.title, .heading, .paragraph, .bullet, .quote]
        )
        XCTAssertEqual(blocks[2].text, "1行目 2行目")
        XCTAssertEqual(blocks[3].text, "項目")
        XCTAssertEqual(blocks[4].text, "引用")
    }

    func testPrivacyManifestDeclaresNoCollectionAndFileTimestampReasons() throws {
        let url = try XCTUnwrap(
            Bundle.kifuLensApplication.url(
                forResource: "PrivacyInfo",
                withExtension: "xcprivacy"
            )
        )
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any]
        )

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(
            manifest["NSPrivacyTrackingDomains"] as? [String],
            []
        )
        let collectedDataTypes = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        )
        XCTAssertTrue(collectedDataTypes.isEmpty)

        let accessedAPIs = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        let fileTimestamp = try XCTUnwrap(
            accessedAPIs.first {
                $0["NSPrivacyAccessedAPIType"] as? String
                    == "NSPrivacyAccessedAPICategoryFileTimestamp"
            }
        )
        let reasons = try XCTUnwrap(
            fileTimestamp["NSPrivacyAccessedAPITypeReasons"] as? [String]
        )
        XCTAssertEqual(Set(reasons), Set(["3B52.1", "C617.1"]))
    }

    func testAppVersionAndEncryptionDeclarationComeFromGeneratedInfo() {
        let info = Bundle.kifuLensApplication.infoDictionary
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "1.0")
        XCTAssertEqual(info?["CFBundleVersion"] as? String, "1")
        XCTAssertEqual(info?["ITSAppUsesNonExemptEncryption"] as? Bool, false)
    }

    func testDistributionTargetsIPhoneOnly() throws {
        let info = try XCTUnwrap(Bundle.kifuLensApplication.infoDictionary)
        let families = try XCTUnwrap(info["UIDeviceFamily"] as? [Int])
        let capabilities = try XCTUnwrap(
            info["UIRequiredDeviceCapabilities"] as? [String]
        )

        XCTAssertEqual(families, [1])
        XCTAssertEqual(
            Set(capabilities),
            Set(["arm64"])
        )
    }

    func testDefaultFileDirectoriesUseKifBookAndReferenceInsideDocuments() throws {
        let documentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
        }
        let directories = KifuLensFileDirectories(
            documentsDirectory: documentsDirectory
        )

        XCTAssertEqual(
            directories.recordDirectory,
            documentsDirectory.appendingPathComponent("kif", isDirectory: true)
        )
        XCTAssertEqual(
            directories.bookDirectory,
            documentsDirectory.appendingPathComponent("book", isDirectory: true)
        )
        XCTAssertEqual(
            directories.referenceDirectory,
            documentsDirectory.appendingPathComponent(
                "reference",
                isDirectory: true
            )
        )

        try directories.prepare()

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directories.recordDirectory.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)

        isDirectory = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directories.bookDirectory.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)

        isDirectory = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directories.referenceDirectory.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

    @MainActor
    func testRecordSaveUsesKifDirectoryWithoutOverwriting() throws {
        let documentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
        }
        let directories = KifuLensFileDirectories(
            documentsDirectory: documentsDirectory
        )
        let saveService = RecordSaveService(
            directory: directories.recordDirectory
        )
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: standardCSAText,
                title: "保存テスト"
            )
        )
        model.goto(ply: 1)

        let url = try saveService.save(
            kifText: try model.exportedKIF(),
            named: "保存テスト"
        )

        XCTAssertEqual(url.deletingLastPathComponent(), directories.recordDirectory)
        XCTAssertEqual(url.lastPathComponent, "保存テスト.kif")
        XCTAssertEqual(model.currentPly, 1)
        XCTAssertEqual(model.record.current.ply, 1)
        XCTAssertEqual(try RecordImportService.load(url: url).record.length, 2)
        XCTAssertThrowsError(
            try saveService.save(
                kifText: try model.exportedKIF(),
                named: "保存テスト.kif"
            )
        ) { error in
            XCTAssertEqual(
                error as? RecordSaveError,
                .fileAlreadyExists("保存テスト.kif")
            )
        }
    }

    @MainActor
    func testOpenedKIFKeepsNameAndOverwritesOnlyAfterRecordChanges() throws {
        let documentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: documentsDirectory)
        }
        let directories = KifuLensFileDirectories(
            documentsDirectory: documentsDirectory
        )
        try directories.prepare()
        let sourceURL = directories.recordDirectory
            .appendingPathComponent("読込元.kif")
        let sourceRecord = try RecordImportService.load(text: standardCSAText)
        let sourceKIF = KakinokiFormatter.exportKIF(sourceRecord.record)
        try sourceKIF.write(to: sourceURL, atomically: true, encoding: .utf8)

        let payload = try RecordImportService.load(url: sourceURL)
        XCTAssertEqual(payload.sourceURL, sourceURL)
        XCTAssertEqual(payload.sourceFileName, "読込元.kif")
        XCTAssertTrue(payload.canOverwriteSource)

        let model = AppModel()
        model.replaceRecord(with: payload)
        XCTAssertEqual(model.preferredRecordSaveFileName, "読込元.kif")

        let baselineKIF = try model.exportedKIF()
        XCTAssertEqual(
            model.saveDisposition(
                for: "読込元.kif",
                kifText: baselineKIF
            ),
            .unchanged
        )
        XCTAssertEqual(
            model.saveDisposition(
                for: "別名.kif",
                kifText: baselineKIF
            ),
            .create
        )

        model.goto(ply: 1)
        XCTAssertEqual(
            model.saveDisposition(
                for: "読込元.kif",
                kifText: try model.exportedKIF()
            ),
            .unchanged
        )
        model.applyBookMove(OpeningBookMove(usi: "8c8d"))
        XCTAssertEqual(
            model.saveDisposition(
                for: "読込元.kif",
                kifText: try model.exportedKIF()
            ),
            .overwrite(sourceURL)
        )
        model.goBack()
        XCTAssertEqual(
            model.saveDisposition(
                for: "読込元.kif",
                kifText: try model.exportedKIF()
            ),
            .unchanged
        )

        model.goto(ply: 2)
        model.applyBookMove(OpeningBookMove(usi: "2g2f"))
        let updatedKIF = try model.exportedKIF()
        XCTAssertEqual(
            model.saveDisposition(
                for: "読込元.kif",
                kifText: updatedKIF
            ),
            .overwrite(sourceURL)
        )

        let saveService = RecordSaveService(
            directory: directories.recordDirectory
        )
        let savedURL = try saveService.overwrite(
            kifText: updatedKIF,
            at: sourceURL
        )
        model.markRecordSaved(at: savedURL, kifText: updatedKIF)

        XCTAssertEqual(
            model.saveDisposition(
                for: "読込元.kif",
                kifText: try model.exportedKIF()
            ),
            .unchanged
        )
        XCTAssertEqual(
            try RecordImportService.load(url: sourceURL).record.length,
            3
        )
    }

    @MainActor
    func testPastedRecordCannotAuthorizeExistingSameNameOverwrite() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: standardCSAText,
                title: "同名"
            )
        )

        XCTAssertNil(model.recordFileName)
        XCTAssertEqual(
            model.saveDisposition(
                for: "同名.kif",
                kifText: try model.exportedKIF()
            ),
            .create
        )
    }

    func testProductScopeIncludesStaticCSAAndExcludesConnectionAndAutoReload() {
        XCTAssertTrue(ProductScope.includedFeatures.contains { $0.contains(".ybb") })
        XCTAssertTrue(ProductScope.includedFeatures.contains { $0.contains("CSA") })
        XCTAssertTrue(ProductScope.includedFeatures.contains { $0.contains("一回取得") })
        XCTAssertTrue(ProductScope.excludedFeatures.contains { $0 == "CSA対局接続" })
        XCTAssertTrue(ProductScope.excludedFeatures.contains { $0.contains("自動再読み込み") })
        XCTAssertTrue(ProductScope.excludedFeatures.contains { $0.contains("編集") })
    }

    func testPortraitBoardUsesFullAvailableWidth() {
        let size = CGSize(width: 430, height: 820)

        XCTAssertEqual(
            WorkspaceLayoutMetrics.portraitBoardWidth(in: size),
            422
        )
        XCTAssertEqual(
            WorkspaceLayoutMetrics.portraitBoardWidth(
                in: CGSize(width: 375, height: 667)
            ),
            367
        )
    }

    func testPlaybackNavigationUsesTwentyPercentMoreWidth() {
        XCTAssertEqual(WorkspaceLayoutMetrics.playbackNavigationWidth, 218)
        XCTAssertEqual(
            WorkspaceLayoutMetrics.playbackNavigationWidth / 182,
            1.2,
            accuracy: 0.01
        )
    }

    func testBundledOpeningBookUsesConciseDisplayName() {
        XCTAssertEqual(BundledOpeningBook.displayName, "ペタショック定跡")
    }

    func testHandPieceSizeUsesEightyFivePercentOfBoardCell() {
        let boardWidth = WorkspaceLayoutMetrics.portraitBoardWidth(
            in: CGSize(width: 375, height: 667)
        )
        let cellSize = BoardLayoutMetrics.cellSize(
            forBoardWidth: boardWidth
        )

        XCTAssertEqual(
            BoardLayoutMetrics.handPieceSize(forBoardWidth: boardWidth),
            CGSize(
                width: cellSize.width * 0.85,
                height: cellSize.height * 0.85
            )
        )
    }

    func testAnalysisMoveArrowUsesRankOneAndKeepsCurrentCompletedResult()
        throws
    {
        let rankTwo = EngineAnalysisLine(
            rank: 2,
            score: nil,
            principalVariation: ["2g2f"],
            depth: 10,
            seldepth: 12,
            nodes: 100,
            nps: 10,
            timeMilliseconds: 10,
            hashfull: 0
        )
        let rankOne = EngineAnalysisLine(
            rank: 1,
            score: nil,
            principalVariation: ["7g7f", "3c3d"],
            depth: 10,
            seldepth: 12,
            nodes: 100,
            nps: 10,
            timeMilliseconds: 10,
            hashfull: 0
        )

        let arrow = try XCTUnwrap(
            AnalysisMoveArrowModel.bestMove(
                state: .analyzing,
                lines: [rankTwo, rankOne],
                sideToMove: .black,
                completedSearchSFEN: nil,
                currentPositionSFEN: "current"
            )
        )

        XCTAssertEqual(
            arrow.source,
            .square(Square(file: 7, rank: 7))
        )
        XCTAssertEqual(
            arrow.destination,
            Square(file: 7, rank: 6)
        )
        XCTAssertNotNil(
            AnalysisMoveArrowModel.bestMove(
                state: .completed,
                lines: [rankOne],
                sideToMove: .black,
                completedSearchSFEN: "current",
                currentPositionSFEN: "current"
            )
        )
        XCTAssertNil(
            AnalysisMoveArrowModel.bestMove(
                state: .completed,
                lines: [rankOne],
                sideToMove: .black,
                completedSearchSFEN: "previous",
                currentPositionSFEN: "current"
            )
        )
    }

    func testAnalysisMoveArrowParsesDropFromSideToMoveHand() throws {
        let arrow = try XCTUnwrap(
            AnalysisMoveArrowModel(
                usiMove: "P*5e",
                color: .white
            )
        )

        XCTAssertEqual(arrow.source, .hand(.pawn, .white))
        XCTAssertEqual(arrow.destination, Square(file: 5, rank: 5))
        XCTAssertNil(
            AnalysisMoveArrowModel(
                usiMove: "resign",
                color: .black
            )
        )
    }

    func testAnalysisMoveArrowLayoutFollowsBoardRotation() {
        let boardWidth: CGFloat = 390
        let normal = AnalysisMoveArrowLayout(
            boardWidth: boardWidth,
            isBoardFlipped: false
        )
        let flipped = AnalysisMoveArrowLayout(
            boardWidth: boardWidth,
            isBoardFlipped: true
        )
        let topLeft = Square(file: 9, rank: 1)

        let normalPoint = normal.squareCenter(topLeft)
        let flippedPoint = flipped.squareCenter(topLeft)
        let cellSize = BoardLayoutMetrics.cellSize(
            forBoardWidth: boardWidth
        )
        let handHeight = BoardLayoutMetrics.handRackHeight(
            forBoardWidth: boardWidth
        )

        XCTAssertEqual(
            normalPoint.x,
            BoardLayoutMetrics.boardFrameInset + cellSize.width / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            normalPoint.y,
            handHeight
                + BoardLayoutMetrics.boardFrameInset
                + BoardLayoutMetrics.coordinateGutter
                + cellSize.height / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            flippedPoint.x,
            BoardLayoutMetrics.boardFrameInset
                + BoardLayoutMetrics.coordinateGutter
                + cellSize.width * 8.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            flippedPoint.y,
            handHeight
                + BoardLayoutMetrics.boardFrameInset
                + cellSize.height * 8.5,
            accuracy: 0.001
        )
    }

    func testAnalysisCandidateRowsShareAvailableHeightAcrossThreeLines() {
        XCTAssertEqual(
            AnalysisLayoutMetrics.candidateMinimumHeight(in: 210),
            70
        )
        XCTAssertEqual(
            AnalysisLayoutMetrics.candidateMinimumHeight(in: -1),
            0
        )
        XCTAssertEqual(
            AnalysisLayoutMetrics.principalVariationLineLimit(
                forCandidateHeight: 49
            ),
            1
        )
        XCTAssertEqual(
            AnalysisLayoutMetrics.principalVariationLineLimit(
                forCandidateHeight: 50
            ),
            2
        )
        XCTAssertEqual(
            AnalysisLayoutMetrics.principalVariationLineLimit(
                forCandidateHeight: 72
            ),
            3
        )
    }

    func testEngineCountsUseThreeSignificantDigits() {
        XCTAssertEqual(EngineMetricFormatting.compactCount(0), "0")
        XCTAssertEqual(EngineMetricFormatting.compactCount(42), "42.0")
        XCTAssertEqual(EngineMetricFormatting.compactCount(999), "999")
        XCTAssertEqual(EngineMetricFormatting.compactCount(1_000), "1.00k")
        XCTAssertEqual(EngineMetricFormatting.compactCount(12_345), "12.3k")
        XCTAssertEqual(EngineMetricFormatting.compactCount(751_000), "751k")
        XCTAssertEqual(EngineMetricFormatting.compactCount(999_999), "1.00M")
        XCTAssertEqual(EngineMetricFormatting.compactCount(5_100_000), "5.10M")
    }

    func testInspectorSwipePageOrder() {
        XCTAssertEqual(
            DetailPanel.allCases.map(\.rawValue),
            ["設定", "棋譜", "解析", "定跡", "前例"]
        )
    }

    func testOpeningBookEvaluationUsesStoredIntegerFormat() {
        XCTAssertEqual(openingBookEvaluationText(70), "+70")
        XCTAssertEqual(openingBookEvaluationText(0), "+0")
        XCTAssertEqual(openingBookEvaluationText(-70), "-70")
    }

    func testOpeningBookEvaluationIsConvertedToBlackPerspective() {
        XCTAssertEqual(
            openingBookEvaluationFromBlackPerspective(
                70,
                sideToMoveIsBlack: true
            ),
            70
        )
        XCTAssertEqual(
            openingBookEvaluationFromBlackPerspective(
                70,
                sideToMoveIsBlack: false
            ),
            -70
        )
    }

    func testEvaluationScoreToneUsesShogiHomeEqualRange() {
        XCTAssertEqual(evaluationScoreTone(200), .blackAdvantage)
        XCTAssertEqual(evaluationScoreTone(199), .equal)
        XCTAssertEqual(evaluationScoreTone(0), .equal)
        XCTAssertEqual(evaluationScoreTone(-199), .equal)
        XCTAssertEqual(evaluationScoreTone(-200), .whiteAdvantage)
    }

    @MainActor
    func testTenPlyNavigationClampsAtRecordEnds() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: """
                position startpos moves 7g7f 3c3d 6g6f 4c4d 5g5f 5c5d \
                4g4f 6c6d 3g3f 7c7d 2g2f 8c8d
                """
            )
        )

        model.goForwardTen()
        XCTAssertEqual(model.currentPly, 10)
        model.goForwardTen()
        XCTAssertEqual(model.currentPly, 12)
        model.goBackTen()
        XCTAssertEqual(model.currentPly, 2)
        model.goBackTen()
        XCTAssertEqual(model.currentPly, 0)
    }

    func testImportsKIFAsReadOnlyRecord() throws {
        let url = temporaryFileURL(fileExtension: "kif")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let kif = """
        開始日時：2024/01/15
        先手：先手
        後手：後手
        手数----指手---------消費時間--
           1 ７六歩(77)   ( 0:00/00:00:00)
           2 ３四歩(33)   ( 0:00/00:00:00)
        """
        try kif.write(to: url, atomically: true, encoding: .utf8)

        let payload = try RecordImportService.load(url: url)

        XCTAssertEqual(payload.title, "fixture")
        XCTAssertEqual(payload.record.length, 2)
        XCTAssertEqual(payload.record.current.ply, 0)
        payload.record.goto(2)
        XCTAssertEqual(payload.record.position.color, .black)
    }

    func testImportsKIFWithShogiHomeComments() throws {
        let kif = """
        手合割：平手\r
        手数----指手---------消費時間--\r
           1 ７六歩(77)\r
        *互角\r
        **評価値=55\r
        **読み筋=△３四歩▲２六歩\r
        """

        let payload = try RecordImportService.load(
            text: "\u{feff}" + kif,
            title: "コメント付きKIF"
        )

        XCTAssertEqual(payload.record.length, 1)
        payload.record.goto(1)
        XCTAssertEqual(
            payload.record.current.comment,
            "互角\n*評価値=55\n*読み筋=△３四歩▲２六歩\n"
        )
    }

    func testImportsKI2AsReadOnlyRecord() throws {
        let url = temporaryFileURL(fileExtension: "ki2")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ki2 = """
        先手：先手
        後手：後手
        ▲７六歩 △３四歩
        """
        try ki2.write(to: url, atomically: true, encoding: .utf8)

        let payload = try RecordImportService.load(url: url)

        XCTAssertEqual(payload.record.length, 2)
        XCTAssertEqual(payload.record.current.ply, 0)
    }

    func testImportsShiftJISKI2AndUTF8KI2U() throws {
        let ki2 = """
        手合割：平手
        ▲７六歩    △３四歩    ▲２六歩    △８四歩
        """
        let shiftJISURL = temporaryFileURL(fileExtension: "ki2")
        let utf8URL = temporaryFileURL(fileExtension: "ki2u")
        defer {
            try? FileManager.default.removeItem(
                at: shiftJISURL.deletingLastPathComponent()
            )
            try? FileManager.default.removeItem(
                at: utf8URL.deletingLastPathComponent()
            )
        }

        try XCTUnwrap(ki2.data(using: .shiftJIS))
            .write(to: shiftJISURL, options: .atomic)
        try ki2.write(to: utf8URL, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try RecordImportService.load(url: shiftJISURL).record.length,
            4
        )
        XCTAssertEqual(
            try RecordImportService.load(url: utf8URL).record.length,
            4
        )
    }

    func testKI2AmbiguousImplicitDropPrefersBoardMove() throws {
        let position = try XCTUnwrap(
            Position.fromSFEN("4k4/9/4n4/9/9/9/9/9/4K4 w n 1")
        )

        let implicitMove = try KakinokiFormatter.parseMoves(
            position: position,
            text: "△４五桂"
        ).get()
        let explicitDrop = try KakinokiFormatter.parseMoves(
            position: position,
            text: "△４五桂打"
        ).get()

        XCTAssertEqual(implicitMove.map(\.usi), ["5c4e"])
        XCTAssertEqual(explicitDrop.map(\.usi), ["N*4e"])
    }

    func testImportsKI2WithPlayerMarkedResignationAndResultLine() throws {
        let ki2 = """
        開始日時：2026/05/07 9:00:00
        終了日時：2026/05/08 18:11:00
        棋戦：名人戦
        場所：石川県七尾市「和倉温泉　日本の宿　のと楽」
        持ち時間：９時間
        消費時間：130▲424△486
        手合割：平手
        先手：糸谷哲郎 九段
        後手：藤井聡太 名人
        戦型：その他の戦型

        ▲２六歩 △８四歩 ▲２五歩 △８五歩 ▲７六歩 △３二金 ▲７七角 △３四歩 ▲６六歩 △３三角
        ▲６八銀 △４二銀 ▲４八銀 △４四歩 ▲７八金 △４三銀 ▲６七銀 △６二銀 ▲１六歩 △１四歩
        ▲３六歩 △７四歩 ▲４六歩 △９四歩 ▲９六歩 △５二金 ▲４七銀 △６四歩 ▲３七桂 △６三銀
        ▲４八金 △４一玉 ▲２九飛 △７三桂 ▲５六歩 △３一玉 ▲５八玉 △８一飛 ▲６八角 △５四銀右
        ▲７七桂 △５一角 ▲４九玉 △８六歩 ▲同　歩 △同　飛 ▲３八玉 △８一飛 ▲５五歩 △６三銀
        ▲５六銀右 △５四歩 ▲同　歩 △同銀右 ▲５五歩 △６三銀 ▲８七歩 △２二玉 ▲４七金 △３三桂
        ▲５七角 △８五桂 ▲同　桂 △同　飛 ▲６八角 △８一飛 ▲２六桂 △３一玉 ▲１五歩 △同　歩
        ▲４五歩 △同　歩 ▲同　桂 △１六歩 ▲３三桂成 △同　角 ▲３五歩 △同　歩 ▲３四歩 △４四角
        ▲２七桂 △４五歩 ▲同　銀 △５三桂 ▲４四銀 △同　銀 ▲３三角 △同　銀 ▲同歩成 △同　金
        ▲３四歩 △３二金 ▲３三銀 △５七歩 ▲同　角 △４五桂 ▲５六銀 △３六歩 ▲４五銀 △同　桂
        ▲４四桂 △３七歩成 ▲同　金 △５六角 ▲４七歩 △３七桂成 ▲同　玉 △３六歩 ▲４八玉 △３七金
        ▲５九玉 △５八銀 ▲同　玉 △４七金 ▲６九玉 △５八銀 ▲７九玉 △７八角成 ▲同　玉 △６七銀成
        ▲同　玉 △８七飛成 ▲７七桂 △５七金 ▲同　玉 △７七龍 ▲６七金 △６八角 ▲５八玉 △４七金
        ▲投了
        まで130手で後手の勝ち
        """

        let payload = try RecordImportService.load(
            text: ki2,
            title: "名人戦"
        )

        XCTAssertEqual(
            payload.record.metadata.getStandardMetadata(.blackName),
            "糸谷哲郎 九段"
        )
        XCTAssertEqual(
            payload.record.metadata.getStandardMetadata(.whiteName),
            "藤井聡太 名人"
        )
        for (ply, expectedUSI) in [
            (96, "N*4e"),
            (100, "5c4e"),
            (112, "S*5h"),
            (116, "S*5h"),
        ] {
            payload.record.goto(ply)
            XCTAssertEqual(
                (payload.record.current.move as? Move)?.usi,
                expectedUSI,
                "\(ply)手目"
            )
        }
        XCTAssertEqual(payload.record.length, 131)
        payload.record.goto(131)
        XCTAssertEqual(
            payload.record.current.move as? SpecialMove,
            specialMove(.resign)
        )
    }

    func testImportsSFENPosition() throws {
        let url = temporaryFileURL(fileExtension: "sfen")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try InitialPositionSFEN.standard.write(to: url, atomically: true, encoding: .utf8)

        let payload = try RecordImportService.load(url: url)

        XCTAssertEqual(payload.record.position.sfen, InitialPositionSFEN.standard)
        XCTAssertEqual(payload.record.length, 0)
    }

    func testImportsUSIRecord() throws {
        let url = temporaryFileURL(fileExtension: "usi")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try "position startpos moves 7g7f 3c3d"
            .write(to: url, atomically: true, encoding: .utf8)

        let payload = try RecordImportService.load(url: url)

        XCTAssertEqual(payload.record.length, 2)
        XCTAssertEqual(payload.record.current.ply, 0)
    }

    func testImportsUSIDeclarationWinAtTerminalPosition() throws {
        let payload = try RecordImportService.load(
            text: "position startpos moves 7g7f 3c3d win",
            title: "宣言勝ち"
        )

        XCTAssertEqual(payload.record.length, 3)
        payload.record.goto(3)
        XCTAssertEqual(
            payload.record.current.move as? SpecialMove,
            specialMove(.enteringOfKing)
        )
    }

    func testImportsCSAFileAsStaticRecord() throws {
        let url = temporaryFileURL(fileExtension: "csa")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try standardCSAText.write(to: url, atomically: true, encoding: .utf8)

        let payload = try RecordImportService.load(url: url)

        XCTAssertEqual(payload.title, "fixture")
        XCTAssertEqual(payload.record.length, 2)
        XCTAssertEqual(
            payload.record.moves.compactMap { ($0.move as? Move)?.usi },
            ["7g7f", "3c3d"]
        )
    }

    func testImportsFloodgateCSAWithMetadataTimesAndResignation() throws {
        let emptyCells = Array(repeating: " * ", count: 9).joined()
        let secondRank = [
            " * ", "-HI", " * ", " * ", " * ",
            " * ", " * ", "-KA", " * ",
        ].joined()
        let eighthRank = [
            " * ", "+KA", " * ", " * ", " * ",
            " * ", " * ", "+HI", " * ",
        ].joined()
        let csa = [
            "V2",
            "N+Murakumo",
            "N-Asanagi",
            "$EVENT:wdoor+floodgate-300-10F+Murakumo+Asanagi",
            "$START_TIME:2026/07/28 08:00:00",
            "P1-KY-KE-GI-KI-OU-KI-GI-KE-KY",
            "P2\(secondRank)",
            "P3-FU-FU-FU-FU-FU-FU-FU-FU-FU",
            "P4\(emptyCells)",
            "P5\(emptyCells)",
            "P6\(emptyCells)",
            "P7+FU+FU+FU+FU+FU+FU+FU+FU+FU",
            "P8\(eighthRank)",
            "P9+KY+KE+GI+KI+OU+KI+GI+KE+KY",
            "+",
            "+7776FU",
            "T11",
            "-3334FU",
            "T15",
            "%TORYO",
        ].joined(separator: "\n")

        let payload = try RecordImportService.load(
            text: csa,
            title: "Floodgate"
        )

        XCTAssertEqual(payload.record.metadata.blackPlayerName, "Murakumo")
        XCTAssertEqual(payload.record.metadata.whitePlayerName, "Asanagi")
        XCTAssertEqual(
            payload.record.metadata.getStandardMetadata(.tournament),
            "wdoor+floodgate-300-10F+Murakumo+Asanagi"
        )
        XCTAssertEqual(
            payload.record.metadata.getStandardMetadata(.startDatetime),
            "2026/07/28 08:00:00"
        )
        let nodes = payload.record.moves.filter { $0.ply > 0 }
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[0].elapsedMs, 11_000)
        XCTAssertEqual(nodes[1].elapsedMs, 15_000)
        XCTAssertEqual(nodes[2].displayText, "投了")
    }

    func testImportsPastedKIFKI2CSAUSIAndSFENText() throws {
        let cases: [(text: String, expectedLength: Int)] = [
            (
                """
                先手：先手
                後手：後手
                手数----指手---------消費時間--
                   1 ７六歩(77)
                   2 ３四歩(33)
                """,
                2
            ),
            ("先手：先手\n後手：後手\n▲７六歩 △３四歩", 2),
            (standardCSAText, 2),
            ("position startpos moves 7g7f 3c3d", 2),
            (InitialPositionSFEN.standard, 0),
        ]

        for (index, testCase) in cases.enumerated() {
            let payload = try RecordImportService.load(
                text: testCase.text,
                title: "貼り付け\(index)"
            )
            XCTAssertEqual(payload.title, "貼り付け\(index)")
            XCTAssertEqual(payload.record.length, testCase.expectedLength)
            XCTAssertEqual(payload.record.current.ply, 0)
        }
    }

    func testPastedEmptyTextReturnsExplicitError() {
        XCTAssertThrowsError(try RecordImportService.load(text: " \n ")) { error in
            XCTAssertEqual(error.localizedDescription, "棋譜テキストが空です。")
        }
    }

    func testWebCSAImporterFetchesExactlyOnceAndParsesRecord() async throws {
        let fetcher = StubWebCSAFetcher(text: standardCSAText)
        let url = try XCTUnwrap(
            URL(string: "https://wdoor.c.u-tokyo.ac.jp/shogi/x/sample.csa")
        )

        let result = try await WebCSAImportService(fetcher: fetcher)
            .importCSA(from: url)

        XCTAssertEqual(fetcher.callCount, 1)
        XCTAssertEqual(result.payload.title, "sample")
        XCTAssertEqual(result.payload.record.length, 2)
        XCTAssertEqual(result.sourceName, "wdoor.c.u-tokyo.ac.jp")
    }

    func testWebCSAImporterDecodesShiftJIS() async throws {
        let data = try XCTUnwrap(standardCSAText.data(using: .shiftJIS))
        let fetcher = StubWebCSAFetcher(
            data: data,
            contentType: "text/plain; charset=Shift_JIS"
        )

        let result = try await WebCSAImportService(fetcher: fetcher)
            .importCSA(from: URL(string: "https://example.com/game.csa")!)

        XCTAssertEqual(result.payload.record.length, 2)
    }

    func testWebCSAImporterRejectsNonCSAAndHTTPError() async {
        let htmlFetcher = StubWebCSAFetcher(
            text: "<!doctype html><html><body>not a record</body></html>",
            contentType: "text/html"
        )
        do {
            _ = try await WebCSAImportService(fetcher: htmlFetcher)
                .importCSA(from: URL(string: "https://example.com/game.csa")!)
            XCTFail("HTMLをCSA棋譜として受理しました")
        } catch let error as WebCSAImportError {
            XCTAssertEqual(error, .csaNotFound)
        } catch {
            XCTFail("想定外のエラーです: \(error)")
        }

        let errorFetcher = StubWebCSAFetcher(text: "Not Found", statusCode: 404)
        do {
            _ = try await WebCSAImportService(fetcher: errorFetcher)
                .importCSA(from: URL(string: "https://example.com/missing.csa")!)
            XCTFail("HTTPエラーを成功として扱いました")
        } catch let error as WebCSAImportError {
            XCTAssertEqual(error, .httpStatus(404))
        } catch {
            XCTFail("想定外のエラーです: \(error)")
        }
    }

    func testWebCSAURLParserAcceptsHTTPSOnly() {
        XCTAssertEqual(
            WebCSAImportService.parseURL(
                from: "説明\nhttps://example.com/game.csa\n"
            )?.absoluteString,
            "https://example.com/game.csa"
        )
        XCTAssertNil(
            WebCSAImportService.parseURL(
                from: "http://wdoor.c.u-tokyo.ac.jp/game.csa"
            )
        )
        XCTAssertNil(WebCSAImportService.parseURL(from: "file:///tmp/game.csa"))
        XCTAssertEqual(
            WebCSAImportService.parseURL(
                from: "https://wdoor.c.u-tokyo.ac.jp/shogi/x/2026/07/28/"
                    + "wdoor+floodgate-300-10F+Murakumo+Asanagi"
                    + "+20260728080004.csa"
            )?.lastPathComponent,
            "wdoor+floodgate-300-10F+Murakumo+Asanagi"
                + "+20260728080004.csa"
        )
    }

    @MainActor
    func testBoardMoveAtRecordEndExtendsRecordDirectly() {
        let model = AppModel()
        let recordSFEN = model.record.position.sfen

        model.tap(square: Square(file: 7, rank: 7))
        XCTAssertEqual(model.selection, .board(Square(file: 7, rank: 7)))
        model.tap(square: Square(file: 7, rank: 6))

        XCTAssertTrue(model.explorationMoves.isEmpty)
        XCTAssertNotEqual(model.position.sfen, recordSFEN)
        XCTAssertEqual(model.record.position.sfen, model.position.sfen)
        XCTAssertEqual(model.record.current.ply, 1)
        XCTAssertEqual(model.currentPly, 1)
    }

    func testBoardTouchLocationMapsOnlyInsideBoardGrid() {
        let size = CGSize(width: 390, height: 429)

        XCTAssertEqual(
            BoardLayoutMetrics.square(
                at: CGPoint(x: 1, y: BoardLayoutMetrics.coordinateGutter + 1),
                in: size
            ),
            Square(file: 9, rank: 1)
        )
        XCTAssertEqual(
            BoardLayoutMetrics.square(
                at: CGPoint(
                    x: size.width - BoardLayoutMetrics.coordinateGutter - 1,
                    y: size.height - 1
                ),
                in: size
            ),
            Square(file: 1, rank: 9)
        )
        XCTAssertNil(
            BoardLayoutMetrics.square(
                at: CGPoint(x: 1, y: BoardLayoutMetrics.coordinateGutter - 1),
                in: size
            )
        )
        XCTAssertNil(
            BoardLayoutMetrics.square(
                at: CGPoint(x: size.width - 1, y: size.height / 2),
                in: size
            )
        )

        XCTAssertEqual(
            BoardLayoutMetrics.square(
                at: CGPoint(
                    x: BoardLayoutMetrics.coordinateGutter + 1,
                    y: 1
                ),
                in: size,
                isBoardFlipped: true
            ),
            Square(file: 1, rank: 9)
        )
        XCTAssertEqual(
            BoardLayoutMetrics.square(
                at: CGPoint(
                    x: size.width - 1,
                    y: size.height - BoardLayoutMetrics.coordinateGutter - 1
                ),
                in: size,
                isBoardFlipped: true
            ),
            Square(file: 9, rank: 1)
        )
        XCTAssertNil(
            BoardLayoutMetrics.square(
                at: CGPoint(x: BoardLayoutMetrics.coordinateGutter - 1, y: 1),
                in: size,
                isBoardFlipped: true
            )
        )
        XCTAssertNil(
            BoardLayoutMetrics.square(
                at: CGPoint(x: size.width / 2, y: size.height - 1),
                in: size,
                isBoardFlipped: true
            )
        )
    }

    @MainActor
    func testPlayerDisplayNamesUseImportedRecordMetadata() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: """
                V2.2
                N+Murakumo
                N-Asanagi
                PI
                +
                """
            )
        )

        XCTAssertEqual(model.playerDisplayName(for: .black), "Murakumo")
        XCTAssertEqual(model.playerDisplayName(for: .white), "Asanagi")
    }

    @MainActor
    func testOptionalPromotionWaitsForImageChoiceAndAppliesSelection() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: "4k4/9/4P4/9/9/9/9/9/4K4 b - 1"
            )
        )

        model.tap(square: Square(file: 5, rank: 3))
        model.tap(square: Square(file: 5, rank: 2))

        XCTAssertNotNil(model.pendingPromotion)
        XCTAssertEqual(model.record.current.ply, 0)
        XCTAssertEqual(
            model.position.board.at(Square(file: 5, rank: 3))?.type,
            .pawn
        )

        model.applyPendingPromotion(promote: true)

        XCTAssertNil(model.pendingPromotion)
        XCTAssertNil(model.selection)
        XCTAssertEqual(model.record.current.ply, 1)
        XCTAssertEqual(
            model.position.board.at(Square(file: 5, rank: 2))?.type,
            .promPawn
        )
    }

    @MainActor
    func testExtendingRecordAtEndAppendsMoveWithoutTemporaryExploration() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: "position startpos moves 7g7f 3c3d"
            )
        )
        model.goto(ply: 2)
        model.applyBookMove(OpeningBookMove(usi: "2g2f"))

        let kif = try model.exportedKIF()

        XCTAssertEqual(model.currentPly, 3)
        XCTAssertEqual(model.record.current.ply, 3)
        XCTAssertEqual(model.record.position.sfen, model.position.sfen)
        XCTAssertTrue(model.explorationMoves.isEmpty)

        let savedRecord = try KakinokiFormatter.importKIF(kif).get()
        XCTAssertEqual(savedRecord.length, 3)
        XCTAssertEqual(
            savedRecord.moves.compactMap { ($0.move as? Move)?.usi },
            ["7g7f", "3c3d", "2g2f"]
        )
    }

    @MainActor
    func testPlayingExistingNextMoveAdvancesRecordWithoutExploration() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: "position startpos moves 7g7f 3c3d"
            )
        )
        model.goto(ply: 1)

        model.applyBookMove(OpeningBookMove(usi: "3c3d"))

        XCTAssertEqual(model.currentPly, 2)
        XCTAssertEqual(model.record.current.ply, 2)
        XCTAssertTrue(model.explorationMoves.isEmpty)
    }

    @MainActor
    func testSavingTemporaryExplorationInMiddleKeepsMainLineAndAddsVariation() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: "position startpos moves 7g7f 3c3d 2g2f 8c8d"
            )
        )
        model.goto(ply: 1)
        model.applyBookMove(OpeningBookMove(usi: "8c8d"))
        model.applyBookMove(OpeningBookMove(usi: "2g2f"))

        let kif = try model.exportedKIF()

        XCTAssertEqual(model.currentPly, 1)
        XCTAssertEqual(model.record.current.ply, 1)
        XCTAssertEqual(model.explorationMoves.map(\.usi), ["8c8d", "2g2f"])
        XCTAssertTrue(kif.contains("変化：2手"))

        let savedRecord = try KakinokiFormatter.importKIF(kif).get()
        let firstMove = try XCTUnwrap(savedRecord.first.next)
        let mainSecondMove = try XCTUnwrap(firstMove.next)
        let variationSecondMove = try XCTUnwrap(mainSecondMove.branch)

        XCTAssertEqual((mainSecondMove.move as? Move)?.usi, "3c3d")
        XCTAssertEqual((variationSecondMove.move as? Move)?.usi, "8c8d")
        XCTAssertEqual(
            (variationSecondMove.next?.move as? Move)?.usi,
            "2g2f"
        )
    }

    @MainActor
    func testIncorporatingTemporaryExplorationSelectsVariationAndKeepsMainLine() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: "position startpos moves 7g7f 3c3d 2g2f 8c8d"
            )
        )
        model.goto(ply: 1)
        model.applyBookMove(OpeningBookMove(usi: "8c8d"))
        model.applyBookMove(OpeningBookMove(usi: "2g2f"))

        model.incorporateExplorationIntoRecord()

        XCTAssertTrue(model.explorationMoves.isEmpty)
        XCTAssertEqual(model.currentPly, 3)
        XCTAssertEqual(model.record.current.ply, 3)
        XCTAssertEqual(model.position.sfen, model.record.position.sfen)
        XCTAssertEqual(
            model.record.movesBefore.compactMap { ($0.move as? Move)?.usi },
            ["7g7f", "8c8d", "2g2f"]
        )

        let firstMove = try XCTUnwrap(model.record.first.next)
        let mainSecondMove = try XCTUnwrap(firstMove.next)
        XCTAssertEqual((mainSecondMove.move as? Move)?.usi, "3c3d")
        XCTAssertEqual((mainSecondMove.branch?.move as? Move)?.usi, "8c8d")

        let selectedLineBeforeSave = model.record.movesBefore.compactMap {
            ($0.move as? Move)?.usi
        }
        let incorporatedKIF = try model.exportedKIF()
        XCTAssertTrue(incorporatedKIF.contains("変化：2手"))
        XCTAssertEqual(
            model.record.movesBefore.compactMap { ($0.move as? Move)?.usi },
            selectedLineBeforeSave
        )
        XCTAssertEqual(model.currentPly, 3)
    }

    func testLicensedPieceAssetsCoverEveryPieceTypeForBothSides() {
        let pieceTypes: [PieceType] = [
            .pawn, .lance, .knight, .silver, .gold, .bishop, .rook, .king,
            .promPawn, .promLance, .promKnight, .promSilver, .horse, .dragon,
        ]

        let blackNames = pieceTypes.map { $0.imageAssetName(color: .black) }
        let whiteNames = pieceTypes.map { $0.imageAssetName(color: .white) }

        XCTAssertEqual(Set(blackNames).count, pieceTypes.count)
        XCTAssertEqual(Set(whiteNames).count, pieceTypes.count)
        XCTAssertTrue(blackNames.allSatisfy { $0.hasPrefix("black_") })
        XCTAssertTrue(whiteNames.allSatisfy { $0.hasPrefix("white_") })
        XCTAssertEqual(PieceType.king.imageAssetName(color: .black), "black_king2")
        XCTAssertEqual(PieceType.king.imageAssetName(color: .white), "white_king")
        XCTAssertEqual(
            PieceType.king.imageAssetName(
                color: .black,
                isBoardFlipped: true
            ),
            "white_king"
        )
        XCTAssertEqual(
            PieceType.king.imageAssetName(
                color: .white,
                isBoardFlipped: true
            ),
            "black_king2"
        )
    }

    func testBoardAndLicensedPieceFilesAreBundledAtExpectedSize() throws {
        let pieceTypes: [PieceType] = [
            .pawn, .lance, .knight, .silver, .gold, .bishop, .rook, .king,
            .promPawn, .promLance, .promKnight, .promSilver, .horse, .dragon,
        ]
        let activeNames = pieceTypes.flatMap { pieceType in
            [
                pieceType.imageAssetName(color: .black),
                pieceType.imageAssetName(color: .white),
            ]
        }
        let names = activeNames + ["black_king", "white_king2"]

        XCTAssertNotNil(Bundle.main.url(forResource: "wood_warm", withExtension: "png"))
        for name in names {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: name, withExtension: "png"),
                "\(name).png がアプリに収録されていません"
            )
            let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
            let pixels = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(pixels.width, 162, "\(name).png の幅が異なります")
            XCTAssertEqual(pixels.height, 180, "\(name).png の高さが異なります")
            XCTAssertNotEqual(pixels.alphaInfo, .none, "\(name).png に透明度がありません")
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "LICENSE", withExtension: "txt"))
    }

    @MainActor
    func testCandidateMoveUsesJapaneseDisplayNotation() {
        let model = AppModel()

        XCTAssertEqual(model.displayText(forUSI: "7g7f"), "☗７六歩(77)")
        XCTAssertEqual(
            model.principalVariationText(
                ["7g7f", "3c3d"],
                droppingFirst: 1
            ),
            "☖３四歩(33)"
        )
        XCTAssertEqual(
            model.principalVariationText(
                ["7g7f", "3c3d", "2g2f"],
                droppingFirst: 1
            ),
            "☖３四歩(33)  ☗２六歩(27)"
        )
        XCTAssertEqual(
            model.principalVariationLabels(
                ["7g7f", "3c3d", "2g2f"],
                droppingFirst: 1
            ),
            ["☖３四歩(33)", "☗２六歩(27)"]
        )
        XCTAssertEqual(
            AnalysisReadingLineFormatting.nonBreakingText(
                for: ["☖３四歩(33)", "☗２六歩(27)"]
            ),
            [
                "☖３四歩(33)".map(String.init).joined(separator: "\u{2060}"),
                "☗２六歩(27)".map(String.init).joined(separator: "\u{2060}")
            ]
            .joined(separator: "  ")
        )
    }

    func testStoredAnalysisCodecReadsKishinAnalyticsCommentFormat() throws {
        let comment = """
        * Engine hisui Version dr5 候補1 深さ 21/36 ノード数 962902 評価値 37 読み筋 △７四歩(73) ▲４七銀(38) △同　歩(23)
        * Engine hisui Version dr5 候補2 深さ 21/30 ノード数 962902 評価値 54 読み筋 △６二銀(71) ▲４七銀(38)

        """

        let analysis = try XCTUnwrap(
            StoredAnalysisCodec.analyses(in: comment).first
        )

        XCTAssertEqual(analysis.engineName, "hisui")
        XCTAssertEqual(analysis.version, "dr5")
        XCTAssertEqual(analysis.lines.map(\.rank), [1, 2])
        XCTAssertEqual(analysis.lines.first?.depth, 21)
        XCTAssertEqual(analysis.lines.first?.seldepth, 36)
        XCTAssertEqual(analysis.lines.first?.nodes, 962_902)
        XCTAssertEqual(analysis.lines.first?.score, .centipawn(37))
        XCTAssertEqual(
            analysis.lines.first?.reading,
            ["△７四歩(73)", "▲４七銀(38)", "△同　歩(23)"]
        )
    }

    func testStoredAnalysisCodecReplacesOnlyNagisaLines() {
        let original = """
        既存コメント
        * Engine hisui Version dr5 候補1 深さ 10/12 ノード数 100 評価値 5 読み筋 ▲７六歩(77)
        * Engine NAGISA Version v3.1 候補1 深さ 8/9 ノード数 50 評価値 1 読み筋 ▲２六歩(27)

        """
        let updated = StoredAnalysisCodec.replacingNagisaLines(
            in: original,
            with: [
                StoredAnalysisLine(
                    rank: 1,
                    depth: 21,
                    seldepth: 36,
                    nodes: 962_902,
                    score: .centipawn(37),
                    reading: ["▲７六歩(77)", "△３四歩(33)"]
                ),
            ]
        )

        XCTAssertTrue(updated.contains("既存コメント"))
        XCTAssertTrue(updated.contains("Engine hisui Version dr5"))
        XCTAssertFalse(updated.contains("深さ 8/9"))
        XCTAssertTrue(
            updated.contains(
                "* Engine NAGISA Version v3.1 候補1 深さ 21/36 "
                    + "ノード数 962902 評価値 37 "
                    + "読み筋 ▲７六歩(77) △３四歩(33)"
            )
        )
    }

    @MainActor
    func testRecordMovesIncludeSourceSquaresInDisplayNotation() throws {
        let model = AppModel()
        model.replaceRecord(
            with: try RecordImportService.load(
                text: "position startpos moves 7g7f 3c3d"
            )
        )

        XCTAssertEqual(
            model.moveNodes.map { model.displayText(for: $0) },
            ["☗７六歩(77)", "☖３四歩(33)"]
        )
    }

    func testUSIInfoParserReadsMultiPVScoreAndMetrics() throws {
        let parsed = try XCTUnwrap(
            USIInfoParser.parse(
                "info depth 18 seldepth 27 multipv 3 score cp -245 "
                    + "nodes 123456 nps 987654 time 125 hashfull 432 "
                    + "pv 7g7f 3c3d 2g2f"
            )
        )

        XCTAssertEqual(parsed.depth, 18)
        XCTAssertEqual(parsed.seldepth, 27)
        XCTAssertEqual(parsed.multipv, 3)
        XCTAssertEqual(parsed.score, .centipawn(-245))
        XCTAssertEqual(parsed.nodes, 123_456)
        XCTAssertEqual(parsed.nps, 987_654)
        XCTAssertEqual(parsed.timeMilliseconds, 125)
        XCTAssertEqual(parsed.hashfull, 432)
        XCTAssertEqual(parsed.principalVariation, ["7g7f", "3c3d", "2g2f"])
    }

    func testUSIInfoParserReadsMateAndBlackPerspective() throws {
        let parsed = try XCTUnwrap(
            USIInfoParser.parse(
                "info depth 31 multipv 1 score mate -7 nodes 900 pv 5a5b"
            )
        )

        XCTAssertEqual(parsed.score, .mate(sign: -1, distance: 7))
        XCTAssertEqual(
            parsed.score?.fromBlackPerspective(sideToMoveIsBlack: false),
            .mate(sign: 1, distance: 7)
        )
    }

    func testEngineScoreUsesShogiHubMateNotation() {
        XCTAssertEqual(
            EngineScore.mate(sign: 1, distance: 7).displayText,
            "+7手詰"
        )
        XCTAssertEqual(
            EngineScore.mate(sign: -1, distance: 7).displayText,
            "-7手詰"
        )
        XCTAssertEqual(
            EngineScore.mate(sign: 1, distance: nil).displayText,
            "詰み"
        )
        XCTAssertEqual(
            EngineScore.mate(sign: -1, distance: nil).displayText,
            "詰み"
        )
    }

    func testNagisaV3AssetsMatchReleaseV31() throws {
        let assets = try NagisaV3Assets.locate()

        XCTAssertEqual(
            try sha256(of: assets.nnue),
            "e6b0b6ac99e95922ceba11633cc8e329968b152d7a79910156405f8a7ea9cdb9"
        )
        XCTAssertEqual(
            try sha256(of: assets.progress),
            "e7ed0eef88868335f9a46c58a121dccb5ad82a5eb1c8ee12de90365ab351e37d"
        )
        let configuration = try XCTUnwrap(AnalysisEngineCatalog.configuration(for: .nagisaV3))
        XCTAssertEqual(configuration.options.first { $0.name == "FV_SCALE" }?.value, "28")
        XCTAssertEqual(configuration.options.first { $0.name == "LS_PROGRESS_COEFF" }?.value, "@progress")
        XCTAssertEqual(configuration.options.first { $0.name == "LS_BUCKET_MODE" }?.value, "progress8kpabs")
    }

    @MainActor
    func testPublicNagisaV3RestartsWithCompleteUSIOptions() async throws {
        let process = EmbeddedUSIProcess.shared
        let assets = try NagisaV3Assets.locate()
        var runs: [[String]] = []

        for _ in 0..<2 {
            let output = LockedLineBuffer()
            XCTAssertTrue(process.start(
                engineDirectory: assets.nnue.deletingLastPathComponent().path
            ) { output.append($0) })
            process.send("usi")
            do {
                try await waitUntil(timeout: 60) {
                    output.lines.contains("usiok")
                }
            } catch {
                await process.shutdown()
                throw error
            }
            await process.shutdown()
            runs.append(output.lines)
        }

        for lines in runs {
            let transcript = lines.joined(separator: "\n")
            XCTAssertTrue(lines.contains { $0.hasPrefix("id name NAGISA_V3 ") }, transcript)
            for name in ["Threads", "USI_Hash", "MultiPV", "LS_PROGRESS_COEFF"] {
                XCTAssertTrue(lines.contains { $0.hasPrefix("option name \(name) ") }, transcript)
            }
        }
        XCTAssertEqual(
            runs[0].filter { $0.hasPrefix("option name ") },
            runs[1].filter { $0.hasPrefix("option name ") }
        )
    }

    @MainActor
    func testPublicNagisaV3FixedNodesSearch() async throws {
        let process = EmbeddedUSIProcess.shared
        let assets = try NagisaV3Assets.locate()
        let output = LockedLineBuffer()

        XCTAssertTrue(
            process.start(
                engineDirectory: assets.nnue.deletingLastPathComponent().path
            ) { line in
                output.append(line)
            }
        )

        do {
            process.send("usi")
            try await waitUntil(timeout: 60) {
                output.lines.contains("usiok")
            }

            let options = [
                ("Threads", "1"),
                ("USI_Hash", "128"),
                ("USI_OwnBook", "false"),
                ("BookFile", "no_book"),
                ("EvalDir", assets.nnue.deletingLastPathComponent().path),
                ("FV_SCALE", "28"),
                ("LS_PROGRESS_COEFF", assets.progress.path),
                ("LS_BUCKET_MODE", "progress8kpabs"),
            ]
            for (name, value) in options {
                process.send("setoption name \(name) value \(value)")
            }
            process.send("isready")
            try await waitUntil(timeout: 120) {
                output.lines.contains("readyok")
            }

            let searchStart = output.lines.count
            process.send("position startpos")
            process.send("go nodes 100000")
            try await waitUntil(timeout: 60) {
                output.lines.dropFirst(searchStart).contains {
                    $0.hasPrefix("bestmove ")
                }
            }
            let searchLines = Array(output.lines.dropFirst(searchStart))
            XCTAssertTrue(
                searchLines.contains { line in
                    guard let nodes = usiValue(after: "nodes", in: line) else {
                        return false
                    }
                    return nodes >= 100_000
                },
                searchLines.suffix(30).joined(separator: "\n")
            )
        } catch {
            await process.shutdown()
            throw error
        }

        await process.shutdown()
    }

    func testAnalysisSettingsStorePersistsInfiniteTime() throws {
        let suiteName = "KifuLensTests.AnalysisSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = AnalysisSettingsStore(defaults: defaults)
        let settings = AnalysisSettings(
            engineIdentifier: .nagisaV3,
            threadCount: 4,
            hashSizeMB: 1_024,
            timeLimit: .infinite
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testAnalysisSettingsStoreFallsBackFromInvalidValues() throws {
        let suiteName = "KifuLensTests.AnalysisSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("unavailable-engine", forKey: "analysis.engineIdentifier")
        defaults.set(8, forKey: "analysis.threadCount")
        defaults.set(2_048, forKey: "analysis.hashSizeMB")
        defaults.set(0, forKey: "analysis.moveTimeSeconds")

        XCTAssertEqual(
            AnalysisSettingsStore(defaults: defaults).load(),
            .default
        )
    }

    @MainActor
    func testAppModelAppliesNagisaV3SettingsAndPersistsThem() async throws {
        let suiteName = "KifuLensTests.AnalysisSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = AnalysisSettingsStore(defaults: defaults)
        let model = AppModel(analysisSettingsStore: store)
        let settings = AnalysisSettings(
            engineIdentifier: .nagisaV3,
            threadCount: 2,
            hashSizeMB: 512,
            timeLimit: .seconds(30)
        )

        let didApply = await model.applyAnalysisSettings(settings)

        XCTAssertTrue(didApply)
        XCTAssertEqual(model.analysisSettings, settings)
        XCTAssertEqual(model.analysisEngine.descriptor.id, .nagisaV3)
        XCTAssertEqual(model.analysisEngine.displayName, "NAGISA v3")
        XCTAssertEqual(store.load(), settings)
    }

    @MainActor
    func testAppModelFallsBackFromUnavailableEngineKeepingAnalysisSettings() throws {
        let suiteName = "KifuLensTests.AnalysisSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unavailable-engine", forKey: "analysis.engineIdentifier")
        defaults.set(2, forKey: "analysis.threadCount")
        defaults.set(512, forKey: "analysis.hashSizeMB")
        defaults.set(30, forKey: "analysis.moveTimeSeconds")
        let model = AppModel(analysisSettingsStore: AnalysisSettingsStore(defaults: defaults))

        XCTAssertEqual(model.analysisSettings, AnalysisSettings(
            engineIdentifier: .nagisaV3,
            threadCount: 2,
            hashSizeMB: 512,
            timeLimit: .seconds(30)
        ))
        XCTAssertEqual(model.analysisEngine.descriptor.id, .nagisaV3)
        XCTAssertEqual(AnalysisEngineCatalog.installedEngines.map(\.id), [.nagisaV3])
    }

    func testAnalysisSettingsIsLeftmostInspectorPanel() {
        XCTAssertEqual(
            DetailPanel.allCases,
            [.settings, .record, .analysis, .book, .precedent]
        )
    }

    func testDotProductCapabilityBit() {
        XCTAssertTrue(
            LocalAnalysisCPUCapabilities.supportsDotProductInstructions(
                in: [0b0000_1000]
            )
        )
        XCTAssertFalse(
            LocalAnalysisCPUCapabilities.supportsDotProductInstructions(
                in: [0b0000_0000]
            )
        )
        XCTAssertFalse(
            LocalAnalysisCPUCapabilities.supportsDotProductInstructions(in: [])
        )
    }

    func testA13DeviceSupportUsesCPUFamilyBoundary() {
        XCTAssertFalse(
            KifuLensDeviceSupport.isA13OrNewer(
                cpuFamily: UInt32(CPUFAMILY_ARM_VORTEX_TEMPEST)
            )
        )
        XCTAssertTrue(
            KifuLensDeviceSupport.isA13OrNewer(
                cpuFamily: UInt32(CPUFAMILY_ARM_LIGHTNING_THUNDER)
            )
        )
        XCTAssertTrue(
            KifuLensDeviceSupport.isA13OrNewer(
                cpuFamily: UInt32(CPUFAMILY_ARM_TUPAI)
            )
        )
    }

    func testEngineBenchmarkStoreRoundTripsDepthResults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = EngineBenchmarkStore(
            fileURL: directory.appendingPathComponent("history.json")
        )
        let measurement = EngineBenchmarkMeasurement(
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_002),
            engine: AnalysisEngineCatalog.nagisaV3,
            configuration: .default,
            command: "go depth 15 × 4",
            buildVariant: "ios-dotprod",
            depthLimit: 15,
            totalTimeMilliseconds: 2_000,
            totalNodes: 4_000_000,
            nodesPerSecond: 2_000_000,
            positions: [
                EngineBenchmarkPositionResult(
                    index: 1,
                    sfen: Position().sfen,
                    depth: 15,
                    seldepth: 27,
                    nodes: 1_000_000,
                    nps: 2_000_000,
                    timeMilliseconds: 500,
                    hashfull: 320,
                    score: "+42",
                    principalVariation: ["7g7f", "3c3d"],
                    bestmove: "7g7f",
                    ponder: "3c3d"
                ),
            ],
            rawTranscript: ["info depth 15", "bestmove 7g7f"],
            progressAsset: "NAGISA_V3/eval/progress.bin",
            bucketMode: "progress8kpabs"
        )
        let environment = EngineBenchmarkEnvironment(
            deviceIdentifier: "iPhone15,4",
            cpuFamily: "0xda33d83d",
            operatingSystem: "iOS 26.0",
            thermalState: "nominal",
            lowPowerModeEnabled: false
        )
        let record = EngineBenchmarkRecord(
            measurement: measurement,
            startingEnvironment: environment,
            endingEnvironment: environment,
            bundle: .kifuLensApplication
        )

        try store.save([record])

        XCTAssertEqual(try store.load(), [record])
    }

    @MainActor
    func testLocalAnalysisEngineRunsTimedUSIBenchCommand()
        async throws
    {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )

        let benchmarkTask = Task {
            try await engine.runBenchmark()
        }
        try await waitUntil {
            process.commands == ["usi"]
        }
        process.emit("usiok")
        try await waitUntil {
            process.commands.last == "isready"
        }
        process.emit(
            "info string loading eval file : "
                + (try NagisaV3Assets.locate().nnue.path)
        )
        process.emit(
            "info string loading progress file : "
                + (try NagisaV3Assets.locate().progress.path)
        )
        process.emit("readyok")
        try await waitUntil {
            Array(process.commands.suffix(2)) == [
                "setoption name MultiPV value 1",
                "isready",
            ]
        }

        process.emit("readyok")
        try await waitUntil {
            process.commands.last
                == "bench 256 1 5000 default movetime"
        }

        for index in EngineBenchmarkConfiguration.positions.indices {
            let number = index + 1
            process.emit(
                "info depth \(20 + number) seldepth \(30 + number) multipv 1 "
                    + "score cp \(number * 10) nodes \(number * 1_000) "
                    + "nps 10000 time \(number * 100) "
                    + "hashfull \(number * 10) pv 7g7f 3c3d"
            )
            process.emit("bestmove 7g7f ponder 3c3d")
        }

        try await waitUntil {
            Array(process.commands.suffix(2)) == [
                "setoption name MultiPV value 3",
                "isready",
            ]
        }
        process.emit("readyok")

        let measurement = try await benchmarkTask.value
        XCTAssertEqual(engine.state, .ready)
        XCTAssertNil(measurement.depthLimit)
        XCTAssertEqual(
            measurement.command,
            "bench 256 1 5000 default movetime"
        )
        XCTAssertEqual(measurement.positions.count, 4)
        XCTAssertEqual(measurement.positions.map(\.depth), [21, 22, 23, 24])
        XCTAssertEqual(measurement.totalNodes, 10_000)
        XCTAssertEqual(measurement.totalTimeMilliseconds, 1_000)
        XCTAssertEqual(measurement.nodesPerSecond, 10_000)
        XCTAssertEqual(measurement.positions.first?.score, "+10")
        XCTAssertEqual(measurement.positions.last?.bestmove, "7g7f")
        XCTAssertTrue(engine.didLoadEvaluationFile)
        XCTAssertTrue(engine.didLoadProgressFile)
    }

    @MainActor
    func testLocalAnalysisEngineRequiresDotProductInstructions() {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            supportsDotProductInstructions: { false },
            availableMemoryBytes: { .max }
        )

        engine.analyze(
            sfen: Position().sfen,
            sideToMoveIsBlack: true
        )

        XCTAssertEqual(
            engine.state,
            .failed(
                "この端末のCPUはNAGISA v3に必要なDotProd命令に対応していません。"
            )
        )
        XCTAssertTrue(process.commands.isEmpty)
    }

    @MainActor
    func testLocalAnalysisEngineRequires256MiBAvailableMemory() {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: {
                LocalAnalysisConfiguration.minimumAvailableMemoryBytes - 1
            }
        )

        engine.analyze(
            sfen: Position().sfen,
            sideToMoveIsBlack: true
        )

        XCTAssertEqual(
            engine.state,
            .failed(
                "端末内解析には256 MB以上の利用可能メモリが必要です。"
                    + "ほかのアプリを終了してから再度お試しください。"
            )
        )
        XCTAssertTrue(process.commands.isEmpty)
    }

    @MainActor
    func testLocalAnalysisEnginePerformsUSIHandshakeAndPreservesStoppedLines() async throws {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: {
                LocalAnalysisConfiguration.minimumAvailableMemoryBytes
            }
        )
        let initial = Position()

        let requestID = engine.analyze(
            sfen: initial.sfen,
            sideToMoveIsBlack: true
        )
        XCTAssertEqual(process.commands, ["usi"])
        XCTAssertEqual(engine.state, .starting)

        process.emit("id name NAGISA_V3 v3.1")
        process.emit("usiok")
        try await waitUntil {
            process.commands.last == "isready"
        }
        XCTAssertEqual(
            Array(process.commands.dropFirst()),
            [
                "setoption name Threads value 1",
                "setoption name USI_Hash value 256",
                "setoption name MultiPV value 3",
                "setoption name USI_Ponder value false",
                "setoption name ConsiderationMode value true",
                "setoption name MaxMovesToDraw value 512",
                "setoption name USI_OwnBook value false",
                "setoption name BookFile value no_book",
                "setoption name EvalDir value \(try NagisaV3Assets.locate().nnue.deletingLastPathComponent().path)",
                "setoption name FV_SCALE value 28",
                "setoption name LS_PROGRESS_COEFF value \(try NagisaV3Assets.locate().progress.path)",
                "setoption name LS_BUCKET_MODE value progress8kpabs",
                "isready",
            ]
        )

        let evaluationPath = try NagisaV3Assets.locate().nnue.path
        let progressPath = try NagisaV3Assets.locate().progress.path
        process.emit("info string loading eval file : \(evaluationPath)")
        process.emit("info string loading progress file : \(progressPath)")
        process.emit("readyok")
        try await waitUntil {
            engine.state == .analyzing
        }
        XCTAssertTrue(engine.didLoadEvaluationFile)
        XCTAssertEqual(engine.loadedEvaluationFilePath, evaluationPath)
        XCTAssertTrue(engine.didLoadProgressFile)
        XCTAssertEqual(engine.loadedProgressFilePath, progressPath)
        XCTAssertEqual(
            Array(process.commands.suffix(3)),
            [
                "usinewgame",
                "position sfen \(initial.sfen)",
                "go movetime 10000",
            ]
        )

        process.emit(
            "info depth 12 seldepth 18 multipv 1 score cp 135 "
                + "nodes 12345 nps 250000 time 49 hashfull 87 "
                + "pv 7g7f 3c3d 2g2f"
        )
        process.emit(
            "info depth 11 seldepth 16 multipv 2 score cp 72 "
                + "nodes 11800 nps 240000 time 49 hashfull 87 "
                + "pv 2g2f 8c8d"
        )
        try await waitUntil {
            engine.lines.count == 2
        }
        XCTAssertEqual(engine.lines.map(\.rank), [1, 2])
        XCTAssertEqual(engine.lines.first?.score, .centipawn(135))
        XCTAssertEqual(engine.lines.first?.principalVariation, ["7g7f", "3c3d", "2g2f"])
        XCTAssertGreaterThan(engine.metrics.nodes, 0)

        process.emit("info depth 13 currmove 8h2b+ currmovenumber 3")
        try await waitUntil {
            engine.metrics.depth == 13
        }
        XCTAssertEqual(engine.metrics.nodes, 11_800)
        XCTAssertEqual(engine.metrics.nps, 240_000)

        engine.stop()
        XCTAssertEqual(engine.state, .stopping)
        XCTAssertEqual(process.commands.last, "stop")
        process.emit(
            "info depth 14 seldepth 20 multipv 1 score cp 144 "
                + "nodes 15000 nps 260000 time 58 hashfull 90 "
                + "pv 7g7f 8c8d"
        )
        process.emit("bestmove 7g7f ponder 3c3d")
        try await waitUntil {
            engine.state == .completed
        }
        XCTAssertEqual(engine.lines.count, 2)
        XCTAssertEqual(engine.lines.first?.depth, 14)
        XCTAssertEqual(engine.completionText, "解析停止")
        XCTAssertEqual(engine.completedSearch?.requestID, requestID)
        XCTAssertEqual(engine.completedSearch?.lines.count, 2)
        XCTAssertTrue(engine.completedSearch?.stoppedByRequest == true)
    }

    @MainActor
    func testLocalAnalysisEngineRejectsReadyWithoutProgressFile() async throws {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )

        engine.analyze(
            sfen: Position().sfen,
            sideToMoveIsBlack: true
        )
        process.emit("usiok")
        try await waitUntil {
            process.commands.last == "isready"
        }
        let evaluationPath = try NagisaV3Assets.locate().nnue.path
        process.emit("info string loading eval file : \(evaluationPath)")
        process.emit("readyok")
        try await waitUntil {
            if case .failed = engine.state {
                return true
            }
            return false
        }

        XCTAssertEqual(
            engine.state,
            .failed(
                "NAGISA v3の進行度係数 progress.bin を"
                    + "指定パスから読み込めませんでした。"
            )
        )
        XCTAssertFalse(process.commands.contains("go movetime 10000"))
    }

    @MainActor
    func testLocalAnalysisEngineRejectsReadyWithoutEvaluationFile() async throws {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )

        engine.analyze(
            sfen: Position().sfen,
            sideToMoveIsBlack: true
        )
        process.emit("usiok")
        try await waitUntil {
            process.commands.last == "isready"
        }
        let progressPath = try NagisaV3Assets.locate().progress.path
        process.emit("info string loading progress file : \(progressPath)")
        process.emit("readyok")
        try await waitUntil {
            if case .failed = engine.state {
                return true
            }
            return false
        }

        XCTAssertEqual(
            engine.state,
            .failed(
                "NAGISA v3の評価関数 nn.bin を"
                    + "指定パスから読み込めませんでした。"
            )
        )
        XCTAssertFalse(process.commands.contains("go movetime 10000"))
    }

    @MainActor
    func testUnknownEngineOptionRemainsAnErrorAfterReady() async throws {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            engineOptions: [EngineUSIOption(name: "UnsupportedOption", value: "1")],
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )
        engine.analyze(sfen: Position().sfen, sideToMoveIsBlack: true)
        process.emit("usiok")
        try await waitUntil { process.commands.last == "isready" }
        process.emit("No such option: UnsupportedOption")
        process.emit("readyok")
        try await waitUntil {
            if case .failed = engine.state { return true }
            return false
        }
        XCTAssertEqual(engine.state, .failed("No such option: UnsupportedOption"))
        XCTAssertFalse(process.commands.contains { $0.hasPrefix("go ") })
        await engine.shutdown()
    }

    @MainActor
    func testLocalAnalysisEngineUsesInfiniteSearchCommand() async throws {
        let process = FakeUSIProcess()
        let settings = AnalysisSettings(
            engineIdentifier: .nagisaV3,
            threadCount: 1,
            hashSizeMB: 256,
            timeLimit: .infinite
        )
        let engine = LocalAnalysisEngine(
            configuration: settings,
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )

        engine.analyze(
            sfen: Position().sfen,
            sideToMoveIsBlack: true
        )
        process.emit("usiok")
        try await waitUntil {
            process.commands.last == "isready"
        }
        let evaluationPath = try NagisaV3Assets.locate().nnue.path
        let progressPath = try NagisaV3Assets.locate().progress.path
        process.emit("info string loading eval file : \(evaluationPath)")
        process.emit("info string loading progress file : \(progressPath)")
        process.emit("readyok")
        try await waitUntil {
            engine.state == .analyzing
        }

        XCTAssertEqual(process.commands.last, "go infinite")
    }

    @MainActor
    func testLocalAnalysisEngineAppliesMaximumHashAndThreadSettings() async throws {
        let process = FakeUSIProcess()
        let settings = AnalysisSettings(
            engineIdentifier: .nagisaV3,
            threadCount: 4,
            hashSizeMB: 1_024,
            timeLimit: .seconds(1)
        )
        let engine = LocalAnalysisEngine(
            configuration: settings,
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )

        engine.analyze(
            sfen: Position().sfen,
            sideToMoveIsBlack: true
        )
        process.emit("usiok")
        try await waitUntil {
            process.commands.last == "isready"
        }

        XCTAssertTrue(
            process.commands.contains("setoption name Threads value 4")
        )
        XCTAssertTrue(
            process.commands.contains("setoption name USI_Hash value 1024")
        )

        let evaluationPath = try NagisaV3Assets.locate().nnue.path
        let progressPath = try NagisaV3Assets.locate().progress.path
        process.emit("info string loading eval file : \(evaluationPath)")
        process.emit("info string loading progress file : \(progressPath)")
        process.emit("readyok")
        try await waitUntil {
            engine.state == .analyzing
        }
        XCTAssertEqual(process.commands.last, "go movetime 1000")
    }

    @MainActor
    func testAnalysisFollowsLatestPositionUntilUserStops() async throws {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )
        let model = AppModel(analysisEngine: engine)
        model.replaceRecord(
            with: try RecordImportService.load(
                text: standardCSAText,
                title: "解析追従テスト"
            )
        )

        model.runAnalysis()
        XCTAssertTrue(model.isAnalysisTrackingPosition)
        process.emit("usiok")
        try await waitUntil {
            process.commands.last == "isready"
        }
        process.emit(
            "info string loading eval file : "
                + (try NagisaV3Assets.locate().nnue.path)
        )
        process.emit(
            "info string loading progress file : "
                + (try NagisaV3Assets.locate().progress.path)
        )
        process.emit("readyok")
        try await waitUntil {
            engine.state == .analyzing
        }

        process.emit(
            "info depth 8 seldepth 10 multipv 1 score cp 40 "
                + "nodes 1000 nps 100000 time 10 hashfull 1 pv 7g7f"
        )
        try await waitUntil {
            engine.lines.count == 1
        }

        model.goto(ply: 1)
        XCTAssertEqual(engine.state, .stopping)
        XCTAssertTrue(engine.lines.isEmpty)
        let stopCount = process.commands.filter { $0 == "stop" }.count

        model.goto(ply: 2)
        model.goto(ply: 1)
        let latestSFEN = model.position.sfen
        XCTAssertEqual(
            process.commands.filter { $0 == "stop" }.count,
            stopCount
        )

        process.emit(
            "info depth 9 seldepth 11 multipv 1 score cp 999 "
                + "nodes 2000 nps 100000 time 20 hashfull 2 pv 7g7f"
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(engine.lines.isEmpty)

        process.emit("bestmove 7g7f")
        try await waitUntil {
            engine.state == .analyzing
                && Array(process.commands.suffix(2)) == [
                    "position sfen \(latestSFEN)",
                    "go movetime 10000",
                ]
        }
        try await waitUntil {
            model.record.first.comment.contains(
                "* Engine NAGISA Version v3.1 候補1 深さ 8/10 "
            )
        }
        XCTAssertTrue(model.record.first.comment.contains("評価値 40"))
        XCTAssertFalse(model.record.first.comment.contains("評価値 999"))

        process.emit(
            "info depth 10 seldepth 12 multipv 1 score cp 100 "
                + "nodes 3000 nps 100000 time 30 hashfull 3 pv 3c3d"
        )
        try await waitUntil {
            engine.lines.count == 1
        }
        XCTAssertEqual(engine.lines.first?.score, .centipawn(-100))

        model.stopAnalysis()
        XCTAssertFalse(model.isAnalysisTrackingPosition)
        let goCount = process.commands.filter {
            $0 == "go movetime 10000"
        }.count
        model.goto(ply: 2)
        process.emit("bestmove 3c3d")
        try await waitUntil {
            engine.state == .ready
        }
        XCTAssertEqual(
            process.commands.filter { $0 == "go movetime 10000" }.count,
            goCount
        )
    }

    @MainActor
    func testCompletedAnalysisIsSavedToKIFAndReloaded() async throws {
        let process = FakeUSIProcess()
        let engine = LocalAnalysisEngine(
            process: process,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )
        let policy = PolicyValueEngine(analyzer: ImmediatePolicyValueAnalyzer())
        let model = AppModel(
            analysisEngine: engine,
            policyValueEngine: policy
        )
        (model.record.first as? Node)?.comment = "既存コメント\n"

        model.runAnalysis()
        process.emit("usiok")
        try await waitUntil {
            process.commands.last == "isready"
        }
        process.emit(
            "info string loading eval file : "
                + (try NagisaV3Assets.locate().nnue.path)
        )
        process.emit(
            "info string loading progress file : "
                + (try NagisaV3Assets.locate().progress.path)
        )
        process.emit("readyok")
        try await waitUntil {
            engine.state == .analyzing
        }
        process.emit(
            "info depth 21 seldepth 36 multipv 1 score cp 37 "
                + "nodes 962902 nps 123456 time 10000 hashfull 200 "
                + "pv 7g7f 3c3d"
        )
        process.emit("bestmove 7g7f ponder 3c3d")
        try await waitUntil {
            model.storedAnalysis?.lines.first?.score == .centipawn(37)
        }

        let kif = try model.exportedKIF()
        XCTAssertTrue(kif.contains("*既存コメント"))
        XCTAssertTrue(
            kif.contains(
                "** Engine NAGISA Version v3.1 候補1 深さ 21/36 "
                    + "ノード数 962902 評価値 37 "
                    + "読み筋 ▲７六歩(77) △３四歩(33)"
            )
        )
        XCTAssertFalse(kif.contains("評価値 +37"))

        let reloaded = try RecordImportService.load(text: kif)
        let analysis = try XCTUnwrap(
            StoredAnalysisCodec.analyses(
                in: reloaded.record.first.comment
            ).last
        )
        XCTAssertEqual(analysis.engineName, "NAGISA")
        XCTAssertEqual(analysis.lines.first?.reading.first, "▲７六歩(77)")

        model.stopAnalysis()
        XCTAssertFalse(model.isAnalysisTrackingPosition)
        XCTAssertEqual(engine.state, .ready)
        XCTAssertTrue(engine.lines.isEmpty)
        XCTAssertEqual(model.storedAnalysis?.lines.first?.score, .centipawn(37))
    }

    @MainActor
    func testAnalysisPanelUsesSavedResultBeforePolicyValue() async throws {
        let policy = PolicyValueEngine(analyzer: UnexpectedPolicyValueAnalyzer())
        let model = AppModel(policyValueEngine: policy)
        (model.record.first as? Node)?.comment =
            StoredAnalysisCodec.replacingNagisaLines(
                in: "",
                with: [
                    StoredAnalysisLine(
                        rank: 1,
                        depth: 12,
                        seldepth: 18,
                        nodes: 1000,
                        score: .centipawn(25),
                        reading: ["▲７六歩(77)"]
                    ),
                ]
            )

        model.detailPanel = .analysis
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.storedAnalysis?.lines.first?.score, .centipawn(25))
        XCTAssertEqual(policy.state, .idle)
    }

    @MainActor
    func testPolicyValueRunsAutomaticallyBeforeAnalysisStarts() async throws {
        let policy = PolicyValueEngine(analyzer: ImmediatePolicyValueAnalyzer())
        let model = AppModel(policyValueEngine: policy)

        XCTAssertEqual(policy.state, .idle)
        model.detailPanel = .analysis
        try await waitUntil {
            policy.state == .ready
        }

        XCTAssertFalse(model.isAnalysisTrackingPosition)
        XCTAssertEqual(policy.result?.moves.count, 2)
        XCTAssertEqual(policy.result?.moves.first?.usi, "7g7f")
    }

    @MainActor
    func testDLSuishoCoreMLReturnsLegalStartPositionPolicies() async throws {
        let policy = PolicyValueEngine()
        let position = Position()

        policy.analyze(sfen: position.sfen)
        try await waitUntil(timeout: 60) {
            policy.state == .ready || {
                if case .failed = policy.state {
                    return true
                }
                return false
            }()
        }
        if case let .failed(message) = policy.state {
            XCTFail("DL水匠のpolicy/value推論に失敗しました: \(message)")
            return
        }

        let result = try XCTUnwrap(policy.result)
        XCTAssertGreaterThan(result.moves.count, 7)
        XCTAssertLessThanOrEqual(
            result.moves.count,
            PolicyValueEngine.maximumCandidateCount
        )
        XCTAssertEqual(
            result.moves.reduce(0) { $0 + $1.probability },
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            result.moves.map(\.rank),
            Array(1...result.moves.count)
        )
        XCTAssertGreaterThanOrEqual(result.sideToMoveWinRate, 0)
        XCTAssertLessThanOrEqual(result.sideToMoveWinRate, 1)
        XCTAssertTrue(
            result.moves.allSatisfy {
                guard let move = position.createMoveByUSI($0.usi) else {
                    return false
                }
                return position.isValidMove(move)
                    && $0.probability >= 0
                    && $0.probability <= 1
            }
        )
        XCTAssertEqual(
            result.moves.map(\.probability),
            result.moves.map(\.probability).sorted(by: >)
        )
        let first = try XCTUnwrap(result.moves.first)
        let second = try XCTUnwrap(result.moves.dropFirst().first)
        XCTAssertEqual(
            log(first.probability / second.probability),
            (first.logit - second.logit) / 1.74,
            accuracy: 0.000_1
        )
    }

    @MainActor
    func testNagisaV3RunsOnDeviceWithoutNetworkAndReturnsBestMove() async throws {
        let engine = LocalAnalysisEngine()
        engine.analyze(
            sfen: Position().sfen,
            sideToMoveIsBlack: true
        )

        try await waitUntil(timeout: 90) {
            if case .failed = engine.state {
                return true
            }
            return engine.didLoadProgressFile
                && engine.lines.contains { $0.nodes > 0 && !$0.principalVariation.isEmpty }
        }
        if case let .failed(message) = engine.state {
            XCTFail("NAGISA_V3の端末内起動に失敗しました: \(message)")
            return
        }

        XCTAssertTrue(engine.engineName.contains("YaneuraOu"))
        XCTAssertEqual(engine.displayName, "NAGISA v3")
        XCTAssertTrue(engine.didLoadProgressFile)
        XCTAssertEqual(
            engine.loadedProgressFilePath,
            try NagisaV3Assets.locate().progress.path
        )
        XCTAssertGreaterThan(engine.metrics.nodes, 0)
        XCTAssertFalse(engine.lines.isEmpty)
        XCTAssertTrue(
            engine.lines.allSatisfy {
                guard let usi = $0.principalVariation.first,
                      let move = Position().createMoveByUSI(usi)
                else {
                    return false
                }
                return Position().isValidMove(move)
            }
        )

        engine.stop()
        try await waitUntil(timeout: 30) {
            engine.state == .completed || {
                if case .failed = engine.state {
                    return true
                }
                return false
            }()
        }
        if case let .failed(message) = engine.state {
            XCTFail("NAGISA_V3の停止に失敗しました: \(message)")
            return
        }
        XCTAssertEqual(engine.state, .completed)
        XCTAssertEqual(engine.completionText, "解析停止")
        XCTAssertFalse(engine.lines.isEmpty)
        await engine.shutdown()
        XCTAssertEqual(engine.state, .idle)
    }

    @MainActor
    func testNagisaV3OneSecondSearchUsesEvaluation() async throws {
        let settings = AnalysisSettings(
            engineIdentifier: .nagisaV3,
            threadCount: 1,
            hashSizeMB: 256,
            timeLimit: .seconds(1)
        )
        let engine = LocalAnalysisEngine(
            configuration: settings,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )
        engine.analyze(
            sfen: Position().sfen,
            sideToMoveIsBlack: true
        )

        try await waitUntil(timeout: 90) {
            engine.state == .completed || {
                if case .failed = engine.state {
                    return true
                }
                return false
            }()
        }
        if case let .failed(message) = engine.state {
            await engine.shutdown()
            XCTFail("NAGISA v3の1秒解析に失敗しました: \(message)")
            return
        }

        XCTAssertEqual(
            engine.loadedEvaluationFilePath,
            try NagisaV3Assets.locate().nnue.path
        )
        XCTAssertEqual(
            engine.loadedProgressFilePath,
            try NagisaV3Assets.locate().progress.path
        )
        XCTAssertGreaterThanOrEqual(engine.metrics.timeMilliseconds, 500)
        XCTAssertLessThan(engine.metrics.depth, 245)
        let centipawnScores = engine.lines.compactMap { line -> Int? in
            guard case let .centipawn(value)? = line.score else {
                return nil
            }
            return value
        }
        XCTAssertFalse(centipawnScores.isEmpty)
        XCTAssertTrue(centipawnScores.contains { $0 != -2 })

        await engine.shutdown()
        XCTAssertEqual(engine.state, .idle)
    }

    @MainActor
    func testNagisaV3TimedBenchCommandUsesEvaluation() async throws {
        let engine = LocalAnalysisEngine(
            configuration: .default,
            supportsDotProductInstructions: { true },
            availableMemoryBytes: { .max }
        )

        let measurement = try await engine.runBenchmark()

        print(
            "NAGISA_V3_BENCHMARK totalNodes=\(measurement.totalNodes) "
                + "totalTimeMs=\(measurement.totalTimeMilliseconds) "
                + "nps=\(measurement.nodesPerSecond)"
        )
        for result in measurement.positions {
            print(
                "NAGISA_V3_BENCHMARK position=\(result.index) "
                    + "nodes=\(result.nodes) timeMs=\(result.timeMilliseconds) "
                    + "nps=\(result.nps) bestmove=\(result.bestmove)"
            )
        }

        XCTAssertNil(measurement.depthLimit)
        XCTAssertEqual(
            measurement.buildVariant,
            "ios-dotprod-a13-lto-prefetch"
        )
        XCTAssertEqual(
            measurement.command,
            "bench 256 1 5000 default movetime"
        )
        XCTAssertEqual(
            measurement.positions.count,
            EngineBenchmarkConfiguration.positions.count
        )
        XCTAssertTrue(
            measurement.positions.allSatisfy {
                $0.depth > 0
                    && $0.nodes > 0
                    && $0.timeMilliseconds > 0
                    && !$0.bestmove.isEmpty
            }
        )
        XCTAssertGreaterThanOrEqual(
            measurement.totalTimeMilliseconds,
            18_000
        )
        XCTAssertGreaterThan(measurement.totalNodes, 0)
        XCTAssertGreaterThan(measurement.totalTimeMilliseconds, 0)
        XCTAssertGreaterThan(measurement.nodesPerSecond, 0)
        XCTAssertEqual(
            engine.loadedEvaluationFilePath,
            try NagisaV3Assets.locate().nnue.path
        )
        XCTAssertEqual(
            engine.loadedProgressFilePath,
            try NagisaV3Assets.locate().progress.path
        )

        await engine.shutdown()
        XCTAssertEqual(engine.state, .idle)
    }

    func testReadsDBOnDemand() throws {
        let url = temporaryFileURL(fileExtension: "db")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let initial = OpeningBookParser.normalizeSFENKey(InitialPositionSFEN.standard)
        let db = """
        \(OpeningBookParser.yaneuraOuHeader)
        sfen \(initial)
        7g7f none 120 22 15
        2g2f none 30 10 4

        """
        try db.write(to: url, atomically: true, encoding: .utf8)

        let session = try OpeningBookSession.open(url: url)
        let moves = try session.moves(for: Position(), ply: 1)

        XCTAssertEqual(session.summary.fileName, "fixture.db")
        XCTAssertTrue(session.summary.isFastEstimate)
        XCTAssertEqual(Set(moves.map(\.usi)), Set(["7g7f", "2g2f"]))
        XCTAssertEqual(moves.first { $0.usi == "7g7f" }?.depth, 22)
        XCTAssertEqual(moves.first { $0.usi == "7g7f" }?.count, 15)
    }

    func testDBUsesIgnoreBookPlyAndFlippedBookLookup() throws {
        let url = temporaryFileURL(fileExtension: "db")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let position = Position()
        let firstMove = try XCTUnwrap(position.createMoveByUSI("7g7f"))
        XCTAssertTrue(position.doMove(firstMove))
        let originalSFEN = position.getSFEN(nextPly: 999)
        let flippedSFEN = try XCTUnwrap(
            OpeningBookParser.flippedSFENKey(
                originalSFEN,
                ignoreBookPly: true
            )
        )
        let flippedMove = try XCTUnwrap(
            OpeningBookParser.flippedUSIMove("3c3d")
        )
        let db = """
        \(OpeningBookParser.yaneuraOuHeader)
        sfen \(flippedSFEN)
        \(flippedMove) none 42 8 3

        """
        try db.write(to: url, atomically: true, encoding: .utf8)

        let session = try OpeningBookSession.open(url: url)
        let moves = try session.moves(for: position, ply: 999)

        XCTAssertEqual(moves.map(\.usi), ["3c3d"])
        XCTAssertEqual(moves.first?.evaluation, 42)
    }

    func testDBMergesAllPlyVariantsBeyondFastOpenSample() throws {
        let url = temporaryFileURL(fileExtension: "db")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let initial = OpeningBookParser.normalizeSFENKey(InitialPositionSFEN.standard)
        var lines = [OpeningBookParser.yaneuraOuHeader]
        for index in 0 ..< YaneuraOuDBReader.fastOpenSamplePositionLimit {
            lines.append(String(format: "sfen a%05d b - 1", index))
        }
        lines.append("sfen \(initial)")
        lines.append("7g7f none 120 22 15")
        lines.append("sfen \(initial.dropLast())3")
        lines.append("2g2f none 30 10 4")
        lines.append("sfen \(initial.dropLast())5")
        lines.append("6g6f none 10 8 2")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)

        let session = try OpeningBookSession.open(url: url)
        let moves = try session.moves(for: Position(), ply: 1)

        XCTAssertEqual(Set(moves.map(\.usi)), Set(["7g7f", "2g2f", "6g6f"]))
    }

    func testReadsYBBOnDemand() throws {
        let url = temporaryFileURL(fileExtension: "ybb")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let initial = OpeningBookParser.normalizeSFENKey(InitialPositionSFEN.standard)
        let book = OpeningBook(
            format: .yaneuraOuDB,
            entries: [
                initial: OpeningBookEntry(
                    moves: [
                        OpeningBookMove(usi: "7g7f", evaluation: 120, depth: 22),
                        OpeningBookMove(usi: "2g2f", evaluation: 30, depth: 10),
                    ],
                    minPly: 1
                ),
            ]
        )
        try OpeningBookParser.writeYaneuraOuBinaryBook(book, to: url)

        let session = try OpeningBookSession.open(url: url)
        let moves = try session.moves(for: Position(), ply: 1)

        XCTAssertEqual(session.summary.fileName, "fixture.ybb")
        XCTAssertEqual(session.summary.positionCount, 1)
        XCTAssertNil(session.summary.moveCount)
        XCTAssertTrue(session.summary.isFastEstimate)
        XCTAssertEqual(moves.map(\.usi), ["7g7f", "2g2f"])
        XCTAssertEqual(moves.first?.evaluation, 120)
        XCTAssertEqual(moves.first?.depth, 22)
        XCTAssertNil(moves.first?.count)
    }

    func testOpeningReferenceSearchesCurrentPositionOnDemand() throws {
        let url = temporaryFileURL(fileExtension: "osref")
        defer {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
            )
        }
        try writeOpeningReferenceFixture(to: url)

        let session = try OpeningReferenceSession.open(url: url)
        let initial = try session.summary(for: Position())

        XCTAssertEqual(session.fileName, "fixture.osref")
        XCTAssertGreaterThan(session.fileSize, 0)
        XCTAssertEqual(initial.occurrenceCount, 10)
        XCTAssertEqual(initial.moves.map(\.usi), ["7g7f"])
        XCTAssertEqual(initial.moves.first?.count, 7)
        XCTAssertEqual(initial.moves.first?.unknownCount, 1)
        XCTAssertEqual(initial.examples.first?.blackName, "先手A")

        let position = Position()
        let move = try XCTUnwrap(position.createMoveByUSI("7g7f"))
        XCTAssertTrue(position.doMove(move))
        let next = try session.summary(for: position)

        XCTAssertEqual(next.occurrenceCount, 5)
        XCTAssertEqual(next.moves.map(\.usi), ["3c3d"])
        XCTAssertEqual(next.examples.first?.outcome, .whiteWin)

        let secondURL = url.deletingLastPathComponent()
            .appendingPathComponent("fixture-2.osref")
        try writeOpeningReferenceFixture(to: secondURL)
        let splitSession = try OpeningReferenceSession.open(
            urls: [secondURL, url]
        )
        let merged = try splitSession.summary(for: Position())

        XCTAssertEqual(splitSession.fileCount, 2)
        XCTAssertTrue(splitSession.fileName.hasSuffix("ほか1件"))
        XCTAssertEqual(merged.occurrenceCount, 20)
        XCTAssertEqual(merged.moves.first?.count, 14)
    }

    func testBundledOpeningReferenceResourcesMatchMetadata() throws {
        XCTAssertEqual(BundledOpeningReference.minimumRating, 4_000)
        XCTAssertEqual(BundledOpeningReference.gameCount, 57_833)
        XCTAssertEqual(BundledOpeningReference.startDate, "2023-01-01")
        XCTAssertEqual(BundledOpeningReference.endDate, "2026-09-05")

        let sources = try BundledOpeningReference.sources(
            in: .kifuLensApplication
        )
        XCTAssertEqual(sources.count, 4)
        XCTAssertEqual(
            sources.map(\.file.compressedByteCount).reduce(0, +),
            268_292_302
        )
        XCTAssertEqual(
            sources.map(\.file.extractedByteCount).reduce(0, +),
            2_910_344_821
        )

        for source in sources {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: source.compressedURL.path
            )
            XCTAssertEqual(
                (attributes[.size] as? NSNumber)?.int64Value,
                source.file.compressedByteCount
            )
            XCTAssertEqual(
                try sha256(of: source.compressedURL),
                source.file.compressedSHA256
            )
            XCTAssertNil(
                Bundle.kifuLensApplication.url(
                    forResource: source.file.resourceName,
                    withExtension: "osref",
                    subdirectory:
                        BundledOpeningReference.resourceSubdirectory
                ) ?? Bundle.kifuLensApplication.url(
                    forResource: source.file.resourceName,
                    withExtension: "osref"
                ),
                "未圧縮の前例ファイルをBundleへ同梱してはいけません"
            )
        }
    }

    @MainActor
    func testReferenceDownloadInstallsReusesAndRestoresOffline() async throws {
        let fixture = try referenceDownloadFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var downloads = 0
        ReferenceDownloadURLProtocol.response = { request in
            if request.url?.lastPathComponent == "catalog.json" {
                return (200, try JSONEncoder().encode(fixture.catalog), "application/json")
            }
            downloads += 1
            return (200, fixture.compressed, "application/octet-stream")
        }
        let catalog = try await fixture.downloader.fetchCatalog(
            from: URL(string: "https://reference.test/catalog.json")!
        )
        let reference = try await fixture.downloader.install(catalog) { _, _, _ in }
        XCTAssertEqual(try reference.summary(for: Position()).occurrenceCount, 10)
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(try fixture.downloader.store.installedCatalog(), catalog)
        XCTAssertTrue(try fixture.downloader.requiredEntries(for: catalog).isEmpty)
        _ = try await fixture.downloader.install(catalog) { _, _, _ in }
        XCTAssertEqual(downloads, 1, "検証済みのファイルを再取得しない")

        let suite = "KifuLensTests.ReferenceDownload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(openingReferenceSelectionStore: .init(defaults: defaults))
        model.openInitialOpeningReferenceIfNeeded(applicationSupportDirectory: fixture.root)
        try await waitUntil { model.precedentState == .loaded || model.presentedError != nil }
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(model.openingReference?.fileName, catalog.displayName)
        XCTAssertEqual(model.precedentSummary?.occurrenceCount, 10)
        XCTAssertEqual(downloads, 1, "次回起動ではネットワークを使わない")
    }

    func testReferenceDownloadFailureAndCancellationKeepPreviousCatalog() async throws {
        let fixture = try referenceDownloadFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ReferenceDownloadURLProtocol.response = { _ in (200, fixture.compressed, "application/octet-stream") }
        _ = try await fixture.downloader.install(fixture.catalog) { _, _, _ in }
        let original = fixture.catalog.files[0].file
        let nextFile = BundledOpeningReferenceFile(
            resourceName: "next", compressedByteCount: original.compressedByteCount,
            compressedSHA256: original.compressedSHA256, extractedFileName: "next.osref",
            extractedByteCount: original.extractedByteCount, extractedSHA256: original.extractedSHA256
        )
        let next = OpeningReferenceCatalog(
            formatVersion: 1, revision: "next", displayName: "更新版",
            startDate: fixture.catalog.startDate, endDate: fixture.catalog.endDate,
            minimumRating: 4_000, gameCount: 10,
            files: [.init(file: nextFile, url: URL(string: "https://reference.test/next")!)]
        )
        ReferenceDownloadURLProtocol.response = { _ in (200, Data("broken".utf8), "application/octet-stream") }
        do {
            _ = try await fixture.downloader.install(next) { _, _, _ in }
            XCTFail("破損した圧縮DBを受け入れてはいけない")
        } catch let error as OpeningReferenceDownloadError {
            guard case .checksum = error else { return XCTFail("想定外のエラー: \(error)") }
        }
        XCTAssertEqual(try fixture.downloader.store.installedCatalog(), fixture.catalog)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.downloader.install(next) { _, _, _ in }
        }
        do { _ = try await task.value; XCTFail("キャンセルが無視された") }
        catch is CancellationError {}
        XCTAssertEqual(try fixture.downloader.store.installedCatalog(), fixture.catalog)
    }

    func testReferenceDownloadRejectsHTTPAndInvalidCatalog() async throws {
        let fixture = try referenceDownloadFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        ReferenceDownloadURLProtocol.response = { _ in (403, Data(), "application/json") }
        do {
            _ = try await fixture.downloader.fetchCatalog(from: URL(string: "https://reference.test/catalog.json")!)
            XCTFail("HTTPエラーを見逃してはいけない")
        } catch let error as OpeningReferenceDownloadError {
            guard case .http(403) = error else { return XCTFail("想定外のエラー: \(error)") }
        }
        let invalid = OpeningReferenceCatalog(
            formatVersion: 1, revision: "invalid", displayName: "不正なURL",
            startDate: fixture.catalog.startDate, endDate: fixture.catalog.endDate,
            minimumRating: 4_000, gameCount: 10,
            files: [.init(file: fixture.catalog.files[0].file, url: URL(string: "http://reference.test/db")!)]
        )
        XCTAssertThrowsError(try invalid.validate())
    }

    private func referenceDownloadFixture() throws -> (
        root: URL, compressed: Data, catalog: OpeningReferenceCatalog,
        downloader: OpeningReferenceDownloader
    ) {
        let url = temporaryFileURL(fileExtension: "osref")
        try writeOpeningReferenceFixture(to: url)
        let data = try Data(contentsOf: url)
        let compressed = try lzfseCompressedData(data)
        let file = BundledOpeningReferenceFile(
            resourceName: "download-fixture", compressedByteCount: Int64(compressed.count),
            compressedSHA256: sha256(of: compressed), extractedFileName: "download-fixture.osref",
            extractedByteCount: Int64(data.count), extractedSHA256: sha256(of: data)
        )
        let catalog = OpeningReferenceCatalog(
            formatVersion: 1, revision: "fixture", displayName: "取得した前例DB",
            startDate: "2023-01-01", endDate: BundledOpeningReference.endDate,
            minimumRating: 4_000, gameCount: 10,
            files: [.init(file: file, url: URL(string: "https://reference.test/db.lzfse")!)]
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReferenceDownloadURLProtocol.self]
        let root = url.deletingLastPathComponent()
        return (root, compressed, catalog, OpeningReferenceDownloader(
            store: .init(applicationSupportDirectory: root),
            session: URLSession(configuration: configuration)
        ))
    }

    @MainActor
    func testBundledOpeningReferenceInstallsAndLoadsByDefault() async throws {
        let sourceURL = temporaryFileURL(fileExtension: "osref")
        let temporaryDirectory = sourceURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try writeOpeningReferenceFixture(to: sourceURL)

        let sourceData = try Data(contentsOf: sourceURL)
        let compressedData = try lzfseCompressedData(sourceData)
        let compressedURL = temporaryDirectory.appendingPathComponent(
            "fixture.osref.lzfse"
        )
        try compressedData.write(to: compressedURL)
        let file = BundledOpeningReferenceFile(
            resourceName: "fixture",
            compressedByteCount: Int64(compressedData.count),
            compressedSHA256: sha256(of: compressedData),
            extractedFileName: "fixture-bundled.osref",
            extractedByteCount: Int64(sourceData.count),
            extractedSHA256: sha256(of: sourceData)
        )
        let source = BundledOpeningReferenceSource(
            file: file,
            compressedURL: compressedURL
        )
        let supportDirectory = temporaryDirectory.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        let suiteName = "KifuLensTests.BundledOpeningReference.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = AppModel(
            openingReferenceSelectionStore: OpeningReferenceSelectionStore(
                defaults: defaults
            )
        )
        model.openInitialOpeningReferenceIfNeeded(
            bundle: Bundle(for: KifuLensTests.self),
            applicationSupportDirectory: supportDirectory,
            bundledSources: [source]
        )
        try await waitUntil {
            model.precedentState == .loaded || model.presentedError != nil
        }

        XCTAssertNil(model.presentedError)
        XCTAssertEqual(
            model.openingReference?.fileName,
            BundledOpeningReference.displayName
        )
        XCTAssertEqual(model.openingReference?.fileCount, 1)
        XCTAssertEqual(model.precedentSummary?.occurrenceCount, 10)
        XCTAssertEqual(model.detailPanel, .record)

        let installedURL = try XCTUnwrap(
            model.openingReference.map { _ in
                supportDirectory
                    .appendingPathComponent(
                        "FloodgateReference",
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        "R4000Since2023",
                        isDirectory: true
                    )
                    .appendingPathComponent(file.extractedFileName)
            }
        )
        XCTAssertEqual(try Data(contentsOf: installedURL), sourceData)
        let installedAttributes = try FileManager.default.attributesOfItem(
            atPath: installedURL.path
        )
        let fileNumber = try XCTUnwrap(
            installedAttributes[.systemFileNumber] as? NSNumber
        )

        let reusedURLs = try await Task.detached {
            try BundledOpeningReferenceInstaller.install(
                sources: [source],
                applicationSupportDirectory: supportDirectory
            )
        }.value
        XCTAssertEqual(reusedURLs, [installedURL])
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(
                atPath: installedURL.path
            )[.systemFileNumber] as? NSNumber,
            fileNumber
        )
        XCTAssertEqual(
            try installedURL
                .deletingLastPathComponent()
                .resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup,
            true
        )
    }

    @MainActor
    func testOpeningReferenceFollowsPositionAndRestoresSelection() async throws {
        let url = temporaryFileURL(fileExtension: "osref")
        defer {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
            )
        }
        try writeOpeningReferenceFixture(to: url)
        let secondURL = url.deletingLastPathComponent()
            .appendingPathComponent("fixture-2.osref")
        try writeOpeningReferenceFixture(to: secondURL)

        let suiteName = "KifuLensTests.OpeningReferenceSelection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var firstModel: AppModel? = AppModel(
            openingReferenceSelectionStore: OpeningReferenceSelectionStore(
                defaults: defaults
            )
        )
        firstModel?.openReferences(
            from: [url, secondURL],
            displayName: "Floodgate全レート",
            selectsPrecedentPanel: false
        )
        try await waitUntil {
            firstModel?.precedentState == .loaded
                || firstModel?.presentedError != nil
        }

        XCTAssertNil(firstModel?.presentedError)
        XCTAssertEqual(firstModel?.openingReference?.fileName, "Floodgate全レート")
        XCTAssertEqual(firstModel?.openingReference?.fileCount, 2)
        XCTAssertEqual(firstModel?.precedentSummary?.moves.map(\.usi), ["7g7f"])
        XCTAssertEqual(firstModel?.precedentSummary?.occurrenceCount, 20)
        XCTAssertEqual(firstModel?.detailPanel, .record)

        firstModel?.detailPanel = .precedent
        firstModel?.applyBookMove(OpeningBookMove(usi: "7g7f"))
        try await waitUntil {
            firstModel?.precedentState == .loaded
                || firstModel?.presentedError != nil
        }

        XCTAssertNil(firstModel?.presentedError)
        XCTAssertEqual(firstModel?.precedentSummary?.moves.map(\.usi), ["3c3d"])
        firstModel = nil

        let restoredDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let restoredModel = AppModel(
            openingReferenceSelectionStore: OpeningReferenceSelectionStore(
                defaults: restoredDefaults
            )
        )
        restoredModel.openInitialOpeningReferenceIfNeeded()
        try await waitUntil {
            restoredModel.precedentState == .loaded
                || restoredModel.presentedError != nil
        }

        XCTAssertNil(restoredModel.presentedError)
        XCTAssertEqual(
            restoredModel.openingReference?.fileName,
            "Floodgate全レート"
        )
        XCTAssertEqual(restoredModel.openingReference?.fileCount, 2)
        XCTAssertEqual(
            restoredModel.precedentSummary?.moves.map(\.usi),
            ["7g7f"]
        )
        XCTAssertEqual(restoredModel.precedentSummary?.occurrenceCount, 20)
    }

    @MainActor
    func testOpeningReferenceKeepsCurrentSelectionWhenReplacementFails() async throws {
        let url = temporaryFileURL(fileExtension: "osref")
        defer {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
            )
        }
        try writeOpeningReferenceFixture(to: url)
        let model = AppModel()
        model.openReference(from: url, selectsPrecedentPanel: false)
        try await waitUntil {
            model.precedentState == .loaded || model.presentedError != nil
        }
        let originalReference = try XCTUnwrap(model.openingReference)

        model.openReference(
            from: url.deletingPathExtension().appendingPathExtension("txt"),
            selectsPrecedentPanel: false
        )
        try await waitUntil {
            model.precedentState == .loaded && model.presentedError != nil
        }

        XCTAssertTrue(model.openingReference === originalReference)
        XCTAssertEqual(model.precedentSummary?.occurrenceCount, 10)
        XCTAssertEqual(model.presentedError?.title, "前例集を開けません")
    }

    @MainActor
    func testLastOpenedBookRestoresAfterAppModelIsRecreated() async throws {
        let url = temporaryFileURL(fileExtension: "ybb")
        defer {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
            )
        }
        let initial = OpeningBookParser.normalizeSFENKey(
            InitialPositionSFEN.standard
        )
        let book = OpeningBook(
            format: .yaneuraOuDB,
            entries: [
                initial: OpeningBookEntry(
                    moves: [
                        OpeningBookMove(
                            usi: "7g7f",
                            evaluation: 120,
                            depth: 22
                        ),
                    ],
                    minPly: 1
                ),
            ]
        )
        try OpeningBookParser.writeYaneuraOuBinaryBook(book, to: url)

        let suiteName = "KifuLensTests.OpeningBookSelection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        var firstModel: AppModel? = AppModel(
            openingBookSelectionStore: OpeningBookSelectionStore(
                defaults: defaults
            )
        )
        firstModel?.openBook(
            from: url,
            displayName: "利用者定跡",
            selectsBookPanel: false
        )
        try await waitUntil {
            guard let firstModel else {
                return false
            }
            return (!firstModel.isOpeningBook
                && !firstModel.isLookingUpBook
                && firstModel.openingBook != nil)
                || firstModel.presentedError != nil
        }

        XCTAssertNil(firstModel?.presentedError)
        XCTAssertEqual(
            firstModel?.openingBookSummary?.fileName,
            "利用者定跡"
        )
        XCTAssertEqual(firstModel?.bookMoves.map(\.usi), ["7g7f"])
        firstModel = nil

        let restoredDefaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        let restoredModel = AppModel(
            openingBookSelectionStore: OpeningBookSelectionStore(
                defaults: restoredDefaults
            )
        )
        restoredModel.openInitialOpeningBookIfNeeded(
            bundle: Bundle(for: KifuLensTests.self)
        )
        try await waitUntil {
            (!restoredModel.isOpeningBook
                && !restoredModel.isLookingUpBook
                && restoredModel.openingBook != nil)
                || restoredModel.presentedError != nil
        }

        XCTAssertNil(restoredModel.presentedError)
        XCTAssertEqual(
            restoredModel.openingBookSummary?.fileName,
            "利用者定跡"
        )
        XCTAssertEqual(restoredModel.bookMoves.map(\.usi), ["7g7f"])
    }

    func testYBBUsesIgnoreBookPlyAndFlippedBookLookup() throws {
        let url = temporaryFileURL(fileExtension: "ybb")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let position = Position()
        let firstMove = try XCTUnwrap(position.createMoveByUSI("7g7f"))
        XCTAssertTrue(position.doMove(firstMove))
        let flippedSFEN = try XCTUnwrap(
            OpeningBookParser.flippedSFENKey(
                position.getSFEN(nextPly: 999),
                ignoreBookPly: true
            )
        )
        let flippedMove = try XCTUnwrap(
            OpeningBookParser.flippedUSIMove("3c3d")
        )
        let book = OpeningBook(
            format: .yaneuraOuDB,
            entries: [
                flippedSFEN: OpeningBookEntry(
                    moves: [
                        OpeningBookMove(
                            usi: flippedMove,
                            evaluation: 42,
                            depth: 8
                        ),
                    ],
                    minPly: 1
                ),
            ]
        )
        try OpeningBookParser.writeYaneuraOuBinaryBook(book, to: url)

        let session = try OpeningBookSession.open(url: url)
        let moves = try session.moves(for: position, ply: 999)

        XCTAssertEqual(moves.map(\.usi), ["3c3d"])
        XCTAssertEqual(moves.first?.evaluation, 42)
    }

    @MainActor
    func testBundledPetaShockBookLoadsByDefaultWithoutChangingPanel() async throws {
        let compressedURL = try XCTUnwrap(
            BundledOpeningBook.compressedURL(
                in: .kifuLensApplication
            )
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: compressedURL.path
        )
        XCTAssertEqual(
            (attributes[.size] as? NSNumber)?.int64Value,
            85_263_832
        )
        XCTAssertEqual(
            try sha256(of: compressedURL),
            "5ebf91f566e97084cc44dafbcda659eaa652862fd3cb8326aefb1cca831d66fa"
        )
        XCTAssertNil(
            Bundle.kifuLensApplication.url(
                forResource: BundledOpeningBook.resourceName,
                withExtension: "db.lzfse",
                subdirectory: BundledOpeningBook.resourceSubdirectory
            )
                ?? Bundle.kifuLensApplication.url(
                    forResource: BundledOpeningBook.resourceName,
                    withExtension: "db.lzfse"
                ),
            "旧DB圧縮資産をアプリBundleへ残してはいけません"
        )
        XCTAssertNil(
            Bundle.kifuLensApplication.url(
                forResource: BundledOpeningBook.resourceName,
                withExtension: "ybb",
                subdirectory: BundledOpeningBook.resourceSubdirectory
            )
                ?? Bundle.kifuLensApplication.url(
                    forResource: BundledOpeningBook.resourceName,
                    withExtension: "ybb"
                ),
            "生YBBをアプリBundleへ同梱してはいけません"
        )

        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "KifuLens-PetaShock-\(UUID().uuidString)",
                isDirectory: true
            )
        let legacyDirectory = supportDirectory
            .appendingPathComponent("OpeningBooks", isDirectory: true)
            .appendingPathComponent("PetaShock233", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let legacyDBURL = legacyDirectory.appendingPathComponent(
            "user_book1.db"
        )
        let legacyMarkerURL = legacyDirectory.appendingPathComponent(
            "user_book1.db.verified"
        )
        try Data("legacy".utf8).write(to: legacyDBURL)
        try Data("legacy".utf8).write(to: legacyMarkerURL)
        defer {
            try? FileManager.default.removeItem(
                at: supportDirectory
            )
        }
        let installedURL = try await Task.detached {
            try BundledOpeningBookInstaller.install(
                from: compressedURL,
                applicationSupportDirectory: supportDirectory
            )
        }.value
        XCTAssertEqual(
            try sha256(of: installedURL),
            BundledOpeningBook.extractedSHA256
        )
        XCTAssertEqual(installedURL.pathExtension, "ybb")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyDBURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyMarkerURL.path)
        )
        let installedAttributes = try FileManager.default.attributesOfItem(
            atPath: installedURL.path
        )
        XCTAssertEqual(
            (installedAttributes[.size] as? NSNumber)?.int64Value,
            BundledOpeningBook.extractedByteCount
        )
        let fileNumber = try XCTUnwrap(
            installedAttributes[.systemFileNumber] as? NSNumber
        )
        try Data("legacy".utf8).write(to: legacyDBURL)
        try Data("legacy".utf8).write(to: legacyMarkerURL)
        let reusedURL = try await Task.detached {
            try BundledOpeningBookInstaller.install(
                from: compressedURL,
                applicationSupportDirectory: supportDirectory
            )
        }.value
        XCTAssertEqual(reusedURL, installedURL)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyDBURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyMarkerURL.path)
        )
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(
                atPath: reusedURL.path
            )[.systemFileNumber] as? NSNumber,
            fileNumber
        )
        XCTAssertEqual(
            try installedURL
                .deletingLastPathComponent()
                .resourceValues(
                    forKeys: [.isExcludedFromBackupKey]
                )
                .isExcludedFromBackup,
            true
        )

        let suiteName = "KifuLensTests.DefaultOpeningBook.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let model = AppModel(
            openingBookSelectionStore: OpeningBookSelectionStore(
                defaults: defaults
            )
        )
        model.openInitialOpeningBookIfNeeded(
            bundle: .kifuLensApplication,
            applicationSupportDirectory: supportDirectory
        )
        try await waitUntil(timeout: 30) {
            (model.openingBook != nil && !model.isLookingUpBook)
                || model.presentedError != nil
        }

        XCTAssertNil(model.presentedError)
        XCTAssertEqual(
            model.openingBookSummary?.fileName,
            BundledOpeningBook.displayName
        )
        XCTAssertEqual(model.detailPanel, .record)
        XCTAssertTrue(model.bookMoves.contains { $0.usi == "2g2f" })
        XCTAssertTrue(model.bookMoves.contains { $0.usi == "7g7f" })

        model.applyBookMove(
            try XCTUnwrap(
                model.bookMoves.first { $0.usi == "7g7f" }
            )
        )
        try await waitUntil(timeout: 10) {
            !model.isLookingUpBook
                || model.presentedError != nil
        }

        XCTAssertNil(model.presentedError)
        XCTAssertTrue(
            model.bookMoves.contains { $0.usi == "3c3d" },
            "実PetaShockの後手局面をFlippedBook相当で検索できません"
        )
    }

    func testYBBWithoutDepthLeavesMissingMetricsHidden() throws {
        let url = temporaryFileURL(fileExtension: "ybb")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let initial = OpeningBookParser.normalizeSFENKey(InitialPositionSFEN.standard)
        let book = OpeningBook(
            format: .yaneuraOuDB,
            entries: [
                initial: OpeningBookEntry(
                    moves: [OpeningBookMove(usi: "7g7f", evaluation: 120, depth: 22)]
                ),
            ]
        )
        try OpeningBookParser.writeYaneuraOuBinaryBook(book, to: url)

        var data = try Data(contentsOf: url)
        data.replaceSubrange(24 ..< 32, with: repeatElement(UInt8(0), count: 8))
        data.removeLast(2)
        try data.write(to: url, options: .atomic)

        let session = try OpeningBookSession.open(url: url)
        let move = try XCTUnwrap(session.moves(for: Position(), ply: 1).first)

        XCTAssertEqual(move.evaluation, 120)
        XCTAssertNil(move.depth)
        XCTAssertNil(move.count)
    }

    func testReadsFixedYaneuraOuYBBVector() throws {
        let url = temporaryFileURL(fileExtension: "ybb")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fixture = """
        59414e452d42494e424f4f4b2d563100
        01000000000000000100000000000000
        58a451220ceb67227e9653221caf447824c22b119e53221ceb6f223e9651220c
        000000000000000001000100
        3b1e78001600
        """
        try XCTUnwrap(data(hex: fixture)).write(to: url, options: .atomic)

        let session = try OpeningBookSession.open(url: url)
        let move = try XCTUnwrap(session.moves(for: Position(), ply: 1).first)

        XCTAssertEqual(move.usi, "7g7f")
        XCTAssertEqual(move.evaluation, 120)
        XCTAssertEqual(move.depth, 22)
    }

    func testRejectsOverflowingYBBRecordCount() throws {
        let url = temporaryFileURL(fileExtension: "ybb")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var fixture = Data("YANE-BINBOOK-V1\0".utf8)
        appendUInt64LE(UInt64(Int.max), to: &fixture)
        appendUInt64LE(1, to: &fixture)
        try fixture.write(to: url, options: .atomic)

        XCTAssertThrowsError(try OpeningBookSession.open(url: url))
    }

    func testRejectsOverflowingYBBMoveOffset() throws {
        let url = temporaryFileURL(fileExtension: "ybb")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fixture = """
        59414e452d42494e424f4f4b2d563100
        01000000000000000100000000000000
        58a451220ceb67227e9653221caf447824c22b119e53221ceb6f223e9651220c
        ffffffffffffffff01000100
        3b1e78001600
        """
        try XCTUnwrap(data(hex: fixture)).write(to: url, options: .atomic)
        let session = try OpeningBookSession.open(url: url)

        XCTAssertThrowsError(try session.moves(for: Position(), ply: 1))
    }

    private func temporaryFileURL(fileExtension: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KifuLensTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("fixture.\(fileExtension)")
    }

    private func writeOpeningReferenceFixture(to url: URL) throws {
        let initialPosition = Position()
        let initialKey = OpeningBookParser.normalizeSFENKey(
            initialPosition.sfen
        )
        let firstMove = try XCTUnwrap(
            initialPosition.createMoveByUSI("7g7f")
        )
        XCTAssertTrue(initialPosition.doMove(firstMove))
        let nextKey = OpeningBookParser.normalizeSFENKey(initialPosition.sfen)

        let firstGameID = "00000000-0000-0000-0000-000000000001"
        let secondGameID = "00000000-0000-0000-0000-000000000002"
        let entries: [(String, [String: Any])] = [
            (
                initialKey,
                [
                    "c": 10,
                    "m": [[
                        "u": "7g7f",
                        "t": "☗７六歩(77)",
                        "c": 7,
                        "b": 4,
                        "w": 2,
                        "d": 0,
                    ]],
                    "e": [[
                        "g": firstGameID,
                        "f": "first.csa",
                        "p": 1,
                        "b": "先手A",
                        "w": "後手A",
                        "d": "2026/08/01 10:00:00",
                        "u": "7g7f",
                        "t": "☗７六歩(77)",
                        "o": "b",
                    ]],
                ]
            ),
            (
                nextKey,
                [
                    "c": 5,
                    "m": [[
                        "u": "3c3d",
                        "t": "☖３四歩(33)",
                        "c": 3,
                        "b": 1,
                        "w": 2,
                        "d": 0,
                    ]],
                    "e": [[
                        "g": secondGameID,
                        "f": "second.csa",
                        "p": 2,
                        "b": "先手B",
                        "w": "後手B",
                        "d": "2026/08/02 10:00:00",
                        "u": "3c3d",
                        "t": "☖３四歩(33)",
                        "o": "w",
                    ]],
                ]
            ),
        ]

        let lines = try entries
            .sorted { $0.0 < $1.0 }
            .map { key, payload in
                let data = try JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.sortedKeys]
                )
                let json = try XCTUnwrap(
                    String(data: data, encoding: .utf8)
                )
                return "\(key)\t\(json)"
            }
        try ("#OPENING-STUDIO-REFERENCE 1\n"
            + lines.joined(separator: "\n")
            + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private var standardCSAText: String {
        """
        V2.2
        N+先手
        N-後手
        PI
        +
        +7776FU
        -3334FU
        """
    }

    private func data(hex: String) -> Data? {
        let compact = hex.filter { !$0.isWhitespace }
        guard compact.count.isMultiple(of: 2) else {
            return nil
        }
        var result = Data()
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index ..< next], radix: 16) else {
                return nil
            }
            result.append(byte)
            index = next
        }
        return result
    }

    private func appendUInt64LE(_ value: UInt64, to data: inout Data) {
        for index in 0 ..< 8 {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(index * 8)))
        }
    }

    private func lzfseCompressedData(_ data: Data) throws -> Data {
        let capacity = max(4_096, data.count * 2)
        let destination = UnsafeMutablePointer<UInt8>.allocate(
            capacity: capacity
        )
        defer {
            destination.deallocate()
        }
        let encodedSize = data.withUnsafeBytes { sourceBytes in
            compression_encode_buffer(
                destination,
                capacity,
                sourceBytes.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                COMPRESSION_LZFSE
            )
        }
        guard encodedSize > 0 else {
            throw NSError(
                domain: "KifuLensTests.LZFSE",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "LZFSEテストデータを圧縮できませんでした。",
                ]
            )
        }
        return Data(bytes: destination, count: encodedSize)
    }

    private func sha256(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()

        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("条件が\(timeout)秒以内に成立しませんでした")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private final class LockedLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var lines: [String] {
        lock.withLock { storage }
    }

    func append(_ line: String) {
        lock.withLock {
            storage.append(line)
        }
    }
}

private func usiValue(after key: Substring, in line: String) -> UInt64? {
    let tokens = line.split(separator: " ")
    guard let index = tokens.firstIndex(of: key),
          tokens.indices.contains(index + 1)
    else {
        return nil
    }
    return UInt64(tokens[index + 1])
}

private final class StubWebCSAFetcher: WebCSADataFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private let statusCode: Int
    private let contentType: String
    private var fetchCount = 0

    var callCount: Int {
        lock.withLock { fetchCount }
    }

    convenience init(
        text: String,
        statusCode: Int = 200,
        contentType: String = "text/plain; charset=utf-8"
    ) {
        self.init(
            data: Data(text.utf8),
            statusCode: statusCode,
            contentType: contentType
        )
    }

    init(
        data: Data,
        statusCode: Int = 200,
        contentType: String = "text/plain; charset=utf-8"
    ) {
        self.data = data
        self.statusCode = statusCode
        self.contentType = contentType
    }

    func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock {
            fetchCount += 1
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (data, response)
    }
}

private final class FakeUSIProcess: USIProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var receiveLine: (@Sendable (String) -> Void)?
    private var sentCommands: [String] = []

    var commands: [String] {
        lock.withLock { sentCommands }
    }

    func start(
        engineDirectory _: String,
        receiveLine: @escaping @Sendable (String) -> Void
    ) -> Bool {
        lock.withLock {
            self.receiveLine = receiveLine
        }
        return true
    }

    func send(_ line: String) {
        lock.withLock {
            sentCommands.append(line)
        }
    }

    func shutdown() async {
        send("quit")
    }

    func emit(_ line: String) {
        let callback = lock.withLock { receiveLine }
        callback?(line)
    }
}

private struct ImmediatePolicyValueAnalyzer: PolicyValueAnalyzing {
    func analyze(sfen _: String, topN _: Int) async throws -> PolicyValueResult {
        PolicyValueResult(
            sideToMoveWinRate: 0.55,
            moves: [
                PolicyValueMove(
                    rank: 1,
                    usi: "7g7f",
                    probability: 0.42,
                    logit: 1.2
                ),
                PolicyValueMove(
                    rank: 2,
                    usi: "2g2f",
                    probability: 0.31,
                    logit: 0.9
                ),
            ]
        )
    }
}

private struct UnexpectedPolicyValueAnalyzer: PolicyValueAnalyzing {
    func analyze(sfen _: String, topN _: Int) async throws -> PolicyValueResult {
        throw PolicyValueError.native("保存済み解析があるため呼ばれてはいけません。")
    }
}

private final class ReferenceDownloadURLProtocol: URLProtocol {
    static var response: ((URLRequest) throws -> (Int, Data, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.response)
            let (status, data, contentType) = try handler(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType, "Content-Length": "\(data.count)"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}

// 公開NAGISA v3.1の参照資産を照合するテスト用の入口。
private extension AnalysisEngineCatalog {
    static var nagisaV3: AnalysisEngineDescriptor { configuration(for: .nagisaV3)!.descriptor }
}

private enum NagisaV3Assets {
    static func locate(in bundle: Bundle = .main) throws -> (nnue: URL, progress: URL) {
        let configuration = try XCTUnwrap(AnalysisEngineCatalog.configuration(for: .nagisaV3))
        let assets = try LocalAnalysisAssets.locate(
            specification: configuration.assets,
            engineName: configuration.descriptor.displayName,
            in: bundle
        )
        return (assets.nnue, try XCTUnwrap(assets.progress))
    }
}
