import Combine
import Foundation
import SwiftShogi

enum RecordSaveDisposition: Equatable {
    case create
    case overwrite(URL)
    case unchanged
}

struct RestoredOpeningBookSelection: Sendable {
    let url: URL
    let displayName: String?
    let bookmarkIsStale: Bool
}

enum OpeningBookSelectionStoreError: LocalizedError {
    case bookmarkCreationFailed(String)
    case bookmarkResolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .bookmarkCreationFailed(reason):
            return "選択した定跡のアクセス情報を保存できませんでした。\(reason)"
        case let .bookmarkResolutionFailed(reason):
            return "前回選択した定跡のアクセス情報を復元できませんでした。\(reason)"
        }
    }
}

struct OpeningBookSelectionStore {
    private enum Key {
        static let bookmark = "selectedOpeningBookBookmark"
        static let displayName = "selectedOpeningBookDisplayName"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(url: URL, displayName: String?) throws {
        let bookmarkData: Data
        do {
            bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw OpeningBookSelectionStoreError.bookmarkCreationFailed(
                error.localizedDescription
            )
        }

        defaults.set(bookmarkData, forKey: Key.bookmark)
        if let displayName, !displayName.isEmpty {
            defaults.set(displayName, forKey: Key.displayName)
        } else {
            defaults.removeObject(forKey: Key.displayName)
        }
    }

    func restore() throws -> RestoredOpeningBookSelection? {
        guard let bookmarkData = defaults.data(forKey: Key.bookmark) else {
            return nil
        }

        do {
            var bookmarkIsStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withoutImplicitStartAccessing],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkIsStale
            )
            return RestoredOpeningBookSelection(
                url: url,
                displayName: defaults.string(forKey: Key.displayName),
                bookmarkIsStale: bookmarkIsStale
            )
        } catch {
            throw OpeningBookSelectionStoreError.bookmarkResolutionFailed(
                error.localizedDescription
            )
        }
    }
}

struct RestoredOpeningReferenceSelection: Sendable {
    let urls: [URL]
    let displayName: String?
    let bookmarkIsStale: Bool
}

enum OpeningReferenceSelectionStoreError: LocalizedError {
    case bookmarkCreationFailed(String)
    case bookmarkResolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .bookmarkCreationFailed(reason):
            return "選択した前例集のアクセス情報を保存できませんでした。\(reason)"
        case let .bookmarkResolutionFailed(reason):
            return "前回選択した前例集のアクセス情報を復元できませんでした。\(reason)"
        }
    }
}

struct OpeningReferenceSelectionStore {
    private enum Key {
        static let bookmarks = "selectedOpeningReferenceBookmarks"
        static let displayName = "selectedOpeningReferenceDisplayName"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func clear() {
        defaults.removeObject(forKey: Key.bookmarks)
        defaults.removeObject(forKey: Key.displayName)
    }

    func save(url: URL, displayName: String?) throws {
        try save(urls: [url], displayName: displayName)
    }

    func save(urls: [URL], displayName: String?) throws {
        let bookmarkData: [Data]
        do {
            bookmarkData = try urls.map {
                try $0.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
        } catch {
            throw OpeningReferenceSelectionStoreError.bookmarkCreationFailed(
                error.localizedDescription
            )
        }

        defaults.set(bookmarkData, forKey: Key.bookmarks)
        if let displayName, !displayName.isEmpty {
            defaults.set(displayName, forKey: Key.displayName)
        } else {
            defaults.removeObject(forKey: Key.displayName)
        }
    }

    func restore() throws -> RestoredOpeningReferenceSelection? {
        guard let bookmarkData = defaults.array(forKey: Key.bookmarks) as? [Data],
              !bookmarkData.isEmpty
        else {
            return nil
        }

        do {
            var bookmarkIsStale = false
            let urls = try bookmarkData.map { data in
                var currentBookmarkIsStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withoutUI, .withoutImplicitStartAccessing],
                    relativeTo: nil,
                    bookmarkDataIsStale: &currentBookmarkIsStale
                )
                bookmarkIsStale = bookmarkIsStale || currentBookmarkIsStale
                return url
            }
            return RestoredOpeningReferenceSelection(
                urls: urls,
                displayName: defaults.string(forKey: Key.displayName),
                bookmarkIsStale: bookmarkIsStale
            )
        } catch {
            throw OpeningReferenceSelectionStoreError.bookmarkResolutionFailed(
                error.localizedDescription
            )
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var record: SwiftShogi.Record
    @Published private(set) var position: Position
    @Published private(set) var recordTitle = "新しい盤面"
    @Published private(set) var recordFileName: String?
    @Published private(set) var currentPly = 0
    @Published private(set) var explorationMoves: [Move] = []
    @Published private(set) var selection: BoardSelection?
    @Published private(set) var availableMoves: [Move] = []
    @Published var pendingPromotion: PendingPromotion?
    @Published private(set) var isAnalysisTrackingPosition = false

    @Published var detailPanel: DetailPanel = .record {
        didSet {
            guard detailPanel != oldValue else {
                return
            }
            refreshContextualAnalysis()
            if detailPanel == .precedent {
                refreshPrecedentSummary()
            }
        }
    }
    @Published private(set) var analysisEngine: LocalAnalysisEngine
    @Published private(set) var analysisSettings: AnalysisSettings
    let policyValueEngine: PolicyValueEngine
    @Published private(set) var storedAnalysis: StoredAnalysis?
    @Published private(set) var engineBenchmarkRecords:
        [EngineBenchmarkRecord]
    @Published private(set) var isRunningEngineBenchmark = false

    @Published private(set) var openingBook: OpeningBookSession?
    @Published private(set) var openingBookSummary: OpeningBookSummary?
    @Published private(set) var bookMoves: [OpeningBookMove] = []
    @Published private(set) var isOpeningBook = false
    @Published private(set) var isLookingUpBook = false

    @Published private(set) var openingReference: OpeningReferenceSession?
    @Published private(set) var precedentSummary: PrecedentSummary?
    @Published private(set) var precedentState: PrecedentLookupState = .idle

    @Published var presentedError: PresentedError?

    private var bookLookupTask: Task<Void, Never>?
    private var precedentLookupTask: Task<Void, Never>?
    private var recordImportTask: Task<Void, Never>?
    private var bookOpenTask: Task<Void, Never>?
    private var referenceOpenTask: Task<Void, Never>?
    private var recordSourceURL: URL?
    private var recordBaselineKIF: String?
    private let openingBookSelectionStore: OpeningBookSelectionStore
    private let openingReferenceSelectionStore: OpeningReferenceSelectionStore
    private let analysisSettingsStore: AnalysisSettingsStore
    private let engineBenchmarkStore: EngineBenchmarkStore
    private var didAttemptInitialOpeningBook = false
    private var didAttemptInitialOpeningReference = false
    private var didAttemptBundledOpeningReference = false
    private var didAttemptBundledOpeningBook = false
    private var analysisEngineCancellable: AnyCancellable?
    private var analysisTargets: [UUID: AnalysisTarget] = [:]

    private struct AnalysisTarget {
        let node: Node
        let previousMove: Move?
    }

    init(
        analysisEngine: LocalAnalysisEngine? = nil,
        policyValueEngine: PolicyValueEngine? = nil,
        openingBookSelectionStore: OpeningBookSelectionStore = OpeningBookSelectionStore(),
        openingReferenceSelectionStore: OpeningReferenceSelectionStore = OpeningReferenceSelectionStore(),
        analysisSettingsStore: AnalysisSettingsStore = AnalysisSettingsStore(),
        engineBenchmarkStore: EngineBenchmarkStore = EngineBenchmarkStore()
    ) {
        let initialRecord = SwiftShogi.Record()
        let loadedBenchmarkRecords: [EngineBenchmarkRecord]
        let benchmarkLoadError: Error?
        do {
            loadedBenchmarkRecords = try engineBenchmarkStore.load()
            benchmarkLoadError = nil
        } catch {
            loadedBenchmarkRecords = []
            benchmarkLoadError = error
        }
        let loadedSettings = analysisEngine == nil
            ? analysisSettingsStore.load()
            : AnalysisSettings.default
        let settings: AnalysisSettings
        if AnalysisEngineCatalog.isAvailableForAnalysis(
            loadedSettings.engineIdentifier
        ) {
            settings = loadedSettings
        } else {
            settings = AnalysisSettings(
                engineIdentifier: AnalysisEngineCatalog.defaultEngine.id,
                threadCount: loadedSettings.threadCount,
                hashSizeMB: loadedSettings.hashSizeMB,
                timeLimit: loadedSettings.timeLimit
            )
            analysisSettingsStore.save(settings)
        }
        self.analysisSettings = settings
        self.analysisEngine = analysisEngine
            ?? AnalysisEngineCatalog.makeEngine(for: settings)
            ?? LocalAnalysisEngine()
        self.policyValueEngine = policyValueEngine ?? PolicyValueEngine()
        self.openingBookSelectionStore = openingBookSelectionStore
        self.openingReferenceSelectionStore = openingReferenceSelectionStore
        self.analysisSettingsStore = analysisSettingsStore
        self.engineBenchmarkStore = engineBenchmarkStore
        engineBenchmarkRecords = loadedBenchmarkRecords
        record = initialRecord
        position = initialRecord.position.clone()
        observeCompletedAnalysis()
        refreshStoredAnalysis()
        if let benchmarkLoadError {
            presentedError = PresentedError(
                title: "ベンチマーク履歴を読み込めません",
                message: benchmarkLoadError.localizedDescription
            )
        }
    }

    var moveNodes: [ImmutableNode] {
        record.moves.filter { $0.ply > 0 }
    }

    var sideToMoveLabel: String {
        position.color == .black ? "先手番" : "後手番"
    }

    func playerDisplayName(for color: SwiftShogi.Color) -> String {
        let value = color == .black
            ? record.metadata.blackPlayerNamePreferShort
            : record.metadata.whitePlayerNamePreferShort
        let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        if trimmed.isEmpty {
            return color == .black ? "先手" : "後手"
        }
        return trimmed
    }

    var displayedPly: Int {
        currentPly + explorationMoves.count
    }

    var preferredRecordSaveFileName: String {
        recordFileName ?? RecordSaveService.suggestedFileName(for: recordTitle)
    }

    var lastMoveDestination: Square? {
        currentPositionLastMove?.to
    }

    func displayText(for move: Move) -> String {
        kifDisplayText(
            for: move,
            previousMove: currentPositionLastMove,
            forReadingLine: false
        )
    }

    func displayText(for node: ImmutableNode) -> String {
        guard let move = node.move as? Move else {
            return node.displayText
        }
        return kifDisplayText(
            for: move,
            previousMove: node.prev?.move as? Move,
            forReadingLine: false
        )
    }

    func displayText(
        forUSI usi: String,
        forReadingLine: Bool = false
    ) -> String {
        guard let move = position.createMoveByUSI(usi) else {
            return usi
        }
        return kifDisplayText(
            for: move,
            previousMove: currentPositionLastMove,
            forReadingLine: forReadingLine
        )
    }

    func principalVariationText(
        _ usis: [String],
        droppingFirst: Int = 0
    ) -> String {
        let labels = principalVariationLabels(
            usis,
            droppingFirst: droppingFirst
        )
        return labels.isEmpty ? "応手なし" : labels.joined(separator: "  ")
    }

    func principalVariationLabels(
        _ usis: [String],
        droppingFirst: Int = 0
    ) -> [String] {
        let snapshot = position.clone()
        var lastMove = currentPositionLastMove
        var labels: [String] = []

        for (index, usi) in usis.enumerated() {
            guard let move = snapshot.createMoveByUSI(usi) else {
                if index >= droppingFirst {
                    labels.append(usi)
                }
                continue
            }

            if index >= droppingFirst {
                labels.append(
                    kifDisplayText(
                        for: move,
                        previousMove: lastMove,
                        forReadingLine: true
                    )
                )
            }
            guard snapshot.doMove(move) else {
                break
            }
            lastMove = move
        }

        return labels
    }

    private func kifDisplayText(
        for move: Move,
        previousMove: Move?,
        forReadingLine: Bool,
        usesKIFPlayerSymbols: Bool = false
    ) -> String {
        let playerSymbol: String
        if usesKIFPlayerSymbols {
            playerSymbol = move.color == .black ? "▲" : "△"
        } else {
            playerSymbol = move.color == .black ? "☗" : "☖"
        }
        var options: [String: Any] = ["prev": previousMove as Any]
        if forReadingLine {
            options["compactSameForPromotionSuffix"] = true
        }
        return playerSymbol
            + KakinokiFormatter.formatKIFMove(move, options: options)
    }

    private var currentPositionLastMove: Move? {
        explorationMoves.last ?? (record.current.move as? Move)
    }

    func importRecord(from url: URL) {
        recordImportTask?.cancel()
        recordImportTask = Task {
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try RecordImportService.load(url: url)
                }.value
                guard !Task.isCancelled else {
                    return
                }

                applyImportedRecord(payload)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                presentedError = PresentedError(
                    title: "棋譜を読み込めません",
                    message: error.localizedDescription
                )
            }
        }
    }

    func replaceRecord(with payload: RecordImportPayload) {
        recordImportTask?.cancel()
        applyImportedRecord(payload)
    }

    func exportedKIF() throws -> String {
        let exportRecord = try makeRecordCopy()

        for move in explorationMoves {
            guard exportRecord.append(
                move,
                option: DoMoveOption(ignoreValidation: true)
            ) else {
                throw RecordExportError.explorationMove(move.usi)
            }
        }

        return insertingInitialPositionComment(
            exportRecord.first.comment,
            into: KakinokiFormatter.exportKIF(exportRecord)
        )
    }

    func saveDisposition(
        for proposedFileName: String,
        kifText: String
    ) -> RecordSaveDisposition {
        guard proposedFileName == recordFileName,
              let recordSourceURL,
              let recordBaselineKIF
        else {
            return .create
        }

        if kifText == recordBaselineKIF {
            return .unchanged
        }
        return .overwrite(recordSourceURL)
    }

    func markRecordSaved(at url: URL, kifText: String) {
        recordFileName = url.lastPathComponent
        recordSourceURL = url
        recordBaselineKIF = kifText
    }

    func openInitialOpeningBookIfNeeded(
        bundle: Bundle = .kifuLensApplication,
        applicationSupportDirectory: URL? = nil
    ) {
        guard !didAttemptInitialOpeningBook,
              openingBook == nil,
              !isOpeningBook
        else {
            return
        }
        didAttemptInitialOpeningBook = true

        do {
            guard let selection = try openingBookSelectionStore.restore() else {
                openBundledOpeningBookIfNeeded(
                    bundle: bundle,
                    applicationSupportDirectory: applicationSupportDirectory
                )
                return
            }

            let onOpened: (@MainActor () throws -> Void)?
            if selection.bookmarkIsStale {
                onOpened = { [openingBookSelectionStore] in
                    try openingBookSelectionStore.save(
                        url: selection.url,
                        displayName: selection.displayName
                    )
                }
            } else {
                onOpened = nil
            }

            startOpeningBookLoad(
                selectsBookPanel: false,
                errorTitle: "前回の定跡を開けません",
                persistenceErrorTitle: "前回の定跡情報を更新できません",
                onOpened: onOpened
            ) {
                try OpeningBookSession.open(
                    url: selection.url,
                    displayName: selection.displayName
                )
            }
        } catch {
            presentedError = PresentedError(
                title: "前回の定跡を開けません",
                message: error.localizedDescription
            )
        }
    }

    func openBundledOpeningBookIfNeeded(
        bundle: Bundle = .kifuLensApplication,
        applicationSupportDirectory: URL? = nil
    ) {
        guard !didAttemptBundledOpeningBook,
              openingBook == nil,
              !isOpeningBook
        else {
            return
        }
        didAttemptBundledOpeningBook = true

        guard let compressedURL = BundledOpeningBook.compressedURL(
            in: bundle
        ) else {
            presentedError = PresentedError(
                title: "既定定跡を開けません",
                message: "同梱した新ペタショック定跡のLZFSEファイルが見つかりません。"
            )
            return
        }
        startOpeningBookLoad(
            selectsBookPanel: false,
            errorTitle: "既定定跡を開けません"
        ) {
            let url = try BundledOpeningBookInstaller.install(
                from: compressedURL,
                applicationSupportDirectory: applicationSupportDirectory
            )
            return try OpeningBookSession.open(
                url: url,
                displayName: BundledOpeningBook.displayName
            )
        }
    }

    func openBook(
        from url: URL,
        displayName: String? = nil,
        selectsBookPanel: Bool = true
    ) {
        startOpeningBookLoad(
            selectsBookPanel: selectsBookPanel,
            errorTitle: "定跡を開けません",
            persistenceErrorTitle: "定跡の選択を保存できません",
            onOpened: { [openingBookSelectionStore] in
                try openingBookSelectionStore.save(
                    url: url,
                    displayName: displayName
                )
            }
        ) {
            try OpeningBookSession.open(
                url: url,
                displayName: displayName
            )
        }
    }

    func openInitialOpeningReferenceIfNeeded(
        bundle: Bundle = .kifuLensApplication,
        applicationSupportDirectory: URL? = nil,
        bundledSources: [BundledOpeningReferenceSource]? = nil
    ) {
        guard !didAttemptInitialOpeningReference,
              openingReference == nil,
              precedentState != .opening
        else {
            return
        }
        didAttemptInitialOpeningReference = true

        do {
            guard let selection = try openingReferenceSelectionStore.restore() else {
                let store = OpeningReferenceDownloadStore(
                    applicationSupportDirectory: applicationSupportDirectory
                )
                if let catalog = try store.installedCatalog(),
                   catalog.endDate >= BundledOpeningReference.endDate {
                    let urls = try store.installedURLs(for: catalog)
                    startOpeningReferenceLoad(
                        selectsPrecedentPanel: false,
                        errorTitle: "ダウンロードした前例DBを開けません"
                    ) {
                        try OpeningReferenceSession.open(urls: urls, displayName: catalog.displayName)
                    }
                    return
                }
                openBundledOpeningReferenceIfNeeded(
                    bundle: bundle,
                    applicationSupportDirectory: applicationSupportDirectory,
                    sources: bundledSources
                )
                return
            }

            let onOpened: (@MainActor () throws -> Void)?
            if selection.bookmarkIsStale {
                onOpened = { [openingReferenceSelectionStore] in
                    try openingReferenceSelectionStore.save(
                        urls: selection.urls,
                        displayName: selection.displayName
                    )
                }
            } else {
                onOpened = nil
            }

            startOpeningReferenceLoad(
                selectsPrecedentPanel: false,
                errorTitle: "前回の前例集を開けません",
                persistenceErrorTitle: "前回の前例集情報を更新できません",
                onOpened: onOpened
            ) {
                try OpeningReferenceSession.open(
                    urls: selection.urls,
                    displayName: selection.displayName
                )
            }
        } catch {
            precedentState = .failed(error.localizedDescription)
            presentedError = PresentedError(
                title: "前回の前例集を開けません",
                message: error.localizedDescription
            )
            openBundledOpeningReferenceIfNeeded(
                bundle: bundle,
                applicationSupportDirectory: applicationSupportDirectory,
                sources: bundledSources
            )
        }
    }

    func openBundledOpeningReferenceIfNeeded(
        bundle: Bundle = .kifuLensApplication,
        applicationSupportDirectory: URL? = nil,
        sources providedSources: [BundledOpeningReferenceSource]? = nil
    ) {
        guard !didAttemptBundledOpeningReference,
              openingReference == nil,
              precedentState != .opening
        else {
            return
        }
        didAttemptBundledOpeningReference = true

        let sources: [BundledOpeningReferenceSource]
        do {
            if let providedSources {
                sources = providedSources
            } else {
                sources = try BundledOpeningReference.sources(in: bundle)
            }
        } catch {
            precedentState = .failed(error.localizedDescription)
            presentedError = PresentedError(
                title: "既定前例集を開けません",
                message: error.localizedDescription
            )
            return
        }

        startOpeningReferenceLoad(
            selectsPrecedentPanel: false,
            errorTitle: "既定前例集を開けません"
        ) {
            let urls = try BundledOpeningReferenceInstaller.install(
                sources: sources,
                applicationSupportDirectory: applicationSupportDirectory
            )
            return try OpeningReferenceSession.open(
                urls: urls,
                displayName: BundledOpeningReference.displayName
            )
        }
    }

    func openReference(
        from url: URL,
        displayName: String? = nil,
        selectsPrecedentPanel: Bool = true
    ) {
        openReferences(
            from: [url],
            displayName: displayName,
            selectsPrecedentPanel: selectsPrecedentPanel
        )
    }

    func useDownloadedOpeningReference(_ session: OpeningReferenceSession) {
        referenceOpenTask?.cancel()
        openingReferenceSelectionStore.clear()
        openingReference = session
        refreshPrecedentSummary()
    }

    func openReferences(
        from urls: [URL],
        displayName: String? = nil,
        selectsPrecedentPanel: Bool = true
    ) {
        startOpeningReferenceLoad(
            selectsPrecedentPanel: selectsPrecedentPanel,
            errorTitle: "前例集を開けません",
            persistenceErrorTitle: "前例集の選択を保存できません",
            onOpened: { [openingReferenceSelectionStore] in
                try openingReferenceSelectionStore.save(
                    urls: urls,
                    displayName: displayName
                )
            }
        ) {
            try OpeningReferenceSession.open(
                urls: urls,
                displayName: displayName
            )
        }
    }

    private func startOpeningReferenceLoad(
        selectsPrecedentPanel: Bool,
        errorTitle: String,
        persistenceErrorTitle: String? = nil,
        onOpened: (@MainActor () throws -> Void)? = nil,
        operation: @escaping @Sendable () throws -> OpeningReferenceSession
    ) {
        referenceOpenTask?.cancel()
        precedentLookupTask?.cancel()
        precedentSummary = nil
        precedentState = .opening
        referenceOpenTask = Task {
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try operation()
                }
                let session = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else {
                    return
                }
                openingReference = session
                do {
                    try onOpened?()
                } catch {
                    presentedError = PresentedError(
                        title: persistenceErrorTitle ?? errorTitle,
                        message: error.localizedDescription
                    )
                }
                if selectsPrecedentPanel {
                    detailPanel = .precedent
                }
                refreshPrecedentSummary()
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                if openingReference == nil {
                    precedentState = .failed(error.localizedDescription)
                } else {
                    refreshPrecedentSummary()
                }
                presentedError = PresentedError(
                    title: errorTitle,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func startOpeningBookLoad(
        selectsBookPanel: Bool,
        errorTitle: String,
        persistenceErrorTitle: String? = nil,
        onOpened: (@MainActor () throws -> Void)? = nil,
        operation: @escaping @Sendable () throws -> OpeningBookSession
    ) {
        bookOpenTask?.cancel()
        bookLookupTask?.cancel()
        bookMoves = []
        isOpeningBook = true
        bookOpenTask = Task {
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try operation()
                }
                let session = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else {
                    return
                }
                openingBook = session
                openingBookSummary = session.summary
                isOpeningBook = false
                do {
                    try onOpened?()
                } catch {
                    presentedError = PresentedError(
                        title: persistenceErrorTitle ?? errorTitle,
                        message: error.localizedDescription
                    )
                }
                if selectsBookPanel {
                    detailPanel = .book
                }
                refreshBookMoves()
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                isOpeningBook = false
                refreshBookMoves()
                presentedError = PresentedError(
                    title: errorTitle,
                    message: error.localizedDescription
                )
            }
        }
    }

    func goto(ply: Int) {
        let clamped = min(max(ply, 0), record.length)
        record.goto(clamped)
        currentPly = record.current.ply
        resetExploration()
    }

    func goBack() {
        if !explorationMoves.isEmpty {
            undoExploration()
        } else {
            goto(ply: currentPly - 1)
        }
    }

    func goForward() {
        guard explorationMoves.isEmpty else {
            return
        }
        goto(ply: currentPly + 1)
    }

    func goBackTen() {
        goto(ply: currentPly - 10)
    }

    func goForwardTen() {
        guard explorationMoves.isEmpty else {
            return
        }
        goto(ply: currentPly + 10)
    }

    func tap(square: Square) {
        if case let .board(from) = selection {
            if from == square {
                clearSelection()
                return
            }

            let targets = availableMoves.filter { $0.to == square }
            if !targets.isEmpty {
                choose(moveFrom: targets)
                return
            }
        } else if case .hand = selection {
            let targets = availableMoves.filter { $0.to == square }
            if let move = targets.first {
                applyMove(move)
                return
            }
        }

        if let piece = position.board.at(square), piece.color == position.color {
            selection = .board(square)
            availableMoves = LegalMoveGenerator.moves(in: position).filter {
                $0.from.leftValue == square
            }
        } else {
            clearSelection()
        }
    }

    func selectHandPiece(_ pieceType: PieceType) {
        if selection == .hand(pieceType) {
            clearSelection()
            return
        }

        selection = .hand(pieceType)
        availableMoves = LegalMoveGenerator.moves(in: position).filter {
            $0.from.rightValue == pieceType
        }
    }

    func isLegalDestination(_ square: Square) -> Bool {
        availableMoves.contains { $0.to == square }
    }

    func applyPendingPromotion(promote: Bool) {
        guard let pendingPromotion else {
            return
        }
        self.pendingPromotion = nil
        applyMove(promote ? pendingPromotion.promoted : pendingPromotion.plain)
    }

    func cancelPendingPromotion() {
        pendingPromotion = nil
        clearSelection()
    }

    func applyBookMove(_ bookMove: OpeningBookMove) {
        guard let move = position.createMoveByUSI(bookMove.usi),
              position.isValidMove(move)
        else {
            presentedError = PresentedError(
                title: "定跡手を盤面へ反映できません",
                message: "\(bookMove.usi) は現在局面の合法手として解釈できませんでした。"
            )
            return
        }
        applyMove(move)
    }

    func resetExploration() {
        position = record.position.clone()
        explorationMoves = []
        handlePositionChange()
    }

    func incorporateExplorationIntoRecord() {
        guard !explorationMoves.isEmpty else {
            return
        }

        for move in explorationMoves {
            guard record.append(
                move,
                option: DoMoveOption(ignoreValidation: true)
            ) else {
                presentedError = PresentedError(
                    title: "一時検討を取り込めません",
                    message: "\(move.usi) を棋譜へ追加できませんでした。"
                )
                return
            }
        }

        currentPly = record.current.ply
        position = record.position.clone()
        explorationMoves = []
        handlePositionChange()
    }

    func runAnalysis() {
        isAnalysisTrackingPosition = true
        policyValueEngine.cancelAndClear()
        analyzeCurrentPosition()
    }

    func runEngineBenchmark() async {
        guard KifuLensDeviceSupport.isCurrentDeviceSupported else {
            presentedError = PresentedError(
                title: "この端末には対応していません",
                message: "ベンチマークはA13以降のiPhoneで実行できます。"
            )
            return
        }
        guard !isAnalysisTrackingPosition,
              !analysisEngine.state.isBusy,
              !isRunningEngineBenchmark
        else {
            presentedError = PresentedError(
                title: "ベンチマークを開始できません",
                message: "端末内解析を停止してから実行してください。"
            )
            return
        }

        isRunningEngineBenchmark = true
        let startingEnvironment = EngineBenchmarkEnvironment.current
        defer {
            isRunningEngineBenchmark = false
        }

        do {
            policyValueEngine.cancelAndClear()
            analysisEngine.cancelAndClear()
            let measurement = try await analysisEngine.runBenchmark()
            let record = EngineBenchmarkRecord(
                measurement: measurement,
                startingEnvironment: startingEnvironment,
                endingEnvironment: .current,
                bundle: .kifuLensApplication
            )
            let nextRecords = [record] + engineBenchmarkRecords
            try engineBenchmarkStore.save(nextRecords)
            engineBenchmarkRecords = nextRecords
            refreshContextualAnalysis()
        } catch {
            presentedError = PresentedError(
                title: "ベンチマークを完了できません",
                message: error.localizedDescription
            )
        }
    }

    func applyAnalysisSettings(_ settings: AnalysisSettings) async -> Bool {
        guard AnalysisSettingsOptions.isValid(settings) else {
            presentedError = PresentedError(
                title: "解析設定を保存できません",
                message: "選択された解析設定を利用できません。"
            )
            return false
        }
        guard AnalysisEngineCatalog.isAvailableForAnalysis(
            settings.engineIdentifier
        ) else {
            presentedError = PresentedError(
                title: "解析エンジンを利用できません",
                message: "このビルドに同梱されたエンジンを選択してください。"
            )
            return false
        }
        guard !isAnalysisTrackingPosition, !analysisEngine.state.isBusy else {
            presentedError = PresentedError(
                title: "解析設定を変更できません",
                message: "端末内解析を停止してから設定を変更してください。"
            )
            return false
        }

        if settings.engineIdentifier != analysisSettings.engineIdentifier {
            await analysisEngine.shutdown()
            guard let nextEngine = AnalysisEngineCatalog.makeEngine(
                for: settings
            ) else {
                presentedError = PresentedError(
                    title: "エンジンを切り替えられません",
                    message: "選択された端末内エンジンが同梱されていません。"
                )
                return false
            }
            analysisEngine = nextEngine
            observeCompletedAnalysis()
        } else {
            analysisEngine.updateConfiguration(settings)
        }

        analysisSettings = settings
        analysisSettingsStore.save(settings)
        refreshContextualAnalysis()
        return true
    }

    private func analyzeCurrentPosition() {
        let requestID = analysisEngine.analyze(
            sfen: position.sfen,
            sideToMoveIsBlack: position.color == .black
        )
        if explorationMoves.isEmpty,
           let node = record.current as? Node
        {
            analysisTargets[requestID] = AnalysisTarget(
                node: node,
                previousMove: node.move as? Move
            )
        }
    }

    func stopAnalysis() {
        isAnalysisTrackingPosition = false
        if analysisEngine.state == .completed {
            analysisEngine.cancelAndClear()
            refreshContextualAnalysis()
        } else {
            analysisEngine.stop()
        }
    }

    func pauseAnalysisForBackground() {
        isAnalysisTrackingPosition = false
        analysisEngine.pauseForBackground()
    }

    func applyAnalysisLine(_ line: EngineAnalysisLine) {
        guard let usi = line.principalVariation.first else {
            return
        }
        applyBookMove(OpeningBookMove(usi: usi))
    }

    private func choose(moveFrom candidates: [Move]) {
        let plain = candidates.first { !$0.promote }
        let promoted = candidates.first { $0.promote }

        if let plain, let promoted {
            pendingPromotion = PendingPromotion(plain: plain, promoted: promoted)
        } else if let move = promoted ?? plain ?? candidates.first {
            applyMove(move)
        }
    }

    private func applyMove(_ move: Move) {
        if explorationMoves.isEmpty {
            let hasRecordedContinuation = record.current.next != nil
            let matchesRecordedContinuation = recordedNextMoves().contains {
                $0.usi == move.usi
            }

            if !hasRecordedContinuation || matchesRecordedContinuation {
                guard record.append(move) else {
                    presentedError = PresentedError(
                        title: "指し手を棋譜へ追加できません",
                        message: "\(move.usi) を棋譜の続きとして追加できませんでした。"
                    )
                    return
                }
                currentPly = record.current.ply
                position = record.position.clone()
                handlePositionChange()
                return
            }
        }

        applyTemporaryExploration(move)
    }

    private func applyTemporaryExploration(_ move: Move) {
        guard position.doMove(move) else {
            presentedError = PresentedError(
                title: "指し手を反映できません",
                message: "\(move.usi) は現在局面では指せません。"
            )
            return
        }
        explorationMoves.append(move)
        handlePositionChange()
    }

    private func recordedNextMoves() -> [Move] {
        var moves: [Move] = []
        var node = record.current.next

        while let current = node {
            if let move = current.move as? Move {
                moves.append(move)
            }
            node = current.branch
        }
        return moves
    }

    private func undoExploration() {
        guard let move = explorationMoves.popLast() else {
            return
        }
        position.undoMove(move)
        handlePositionChange()
    }

    private func clearSelection() {
        selection = nil
        availableMoves = []
    }

    private func makeRecordCopy() throws -> SwiftShogi.Record {
        let copy = SwiftShogi.Record(position: record.initialPosition.clone())
        copy.metadata = copyMetadata(record.metadata)
        copyNodeData(from: record.first, to: copy.first)
        try copyChildren(from: record.first, into: copy)

        for sourceNode in record.movesBefore.dropFirst() {
            guard copy.append(
                sourceNode.move,
                option: DoMoveOption(ignoreValidation: true)
            ) else {
                throw RecordExportError.currentLine(sourceNode.ply)
            }
        }

        return copy
    }

    private func copyChildren(
        from sourceParent: ImmutableNode,
        into copy: SwiftShogi.Record
    ) throws {
        var sourceChild = sourceParent.next

        while let child = sourceChild {
            guard copy.append(
                child.move,
                option: DoMoveOption(ignoreValidation: true)
            ) else {
                throw RecordExportError.recordMove(child.ply)
            }

            copyNodeData(from: child, to: copy.current)
            try copyChildren(from: child, into: copy)

            guard copy.goBack() else {
                throw RecordExportError.recordMove(child.ply)
            }
            sourceChild = child.branch
        }
    }

    private func insertingInitialPositionComment(
        _ comment: String,
        into kif: String
    ) -> String {
        guard !comment.isEmpty,
              let headerRange = kif.range(
                of: "手数----指手---------消費時間--\n"
              )
        else {
            return kif
        }

        let lines = comment
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast(comment.hasSuffix("\n") ? 1 : 0)
            .map { "*\($0)\n" }
            .joined()
        var result = kif
        result.insert(contentsOf: lines, at: headerRange.upperBound)
        return result
    }

    private func copyMetadata(
        _ source: ImmutableRecordMetadata
    ) -> RecordMetadata {
        let metadata = RecordMetadata()

        for key in source.standardMetadataKeys {
            metadata.setStandardMetadata(
                key,
                value: source.getStandardMetadata(key)
            )
        }
        for key in source.customMetadataKeys {
            metadata.setCustomMetadata(
                key,
                value: source.getCustomMetadata(key)
            )
        }

        return metadata
    }

    private func copyNodeData(
        from source: ImmutableNode,
        to destination: ImmutableNode
    ) {
        guard let destination = destination as? Node else {
            return
        }

        destination.comment = source.comment
        destination.bookmark = source.bookmark
        destination.customData = source.customData
        destination.setElapsedMs(source.elapsedMs)
    }

    private func applyImportedRecord(_ payload: RecordImportPayload) {
        analysisTargets.removeAll()
        record = payload.record
        record.goto(0)
        recordTitle = payload.title
        currentPly = 0
        resetExploration()
        detailPanel = .record

        if payload.canOverwriteSource {
            recordFileName = payload.sourceFileName
            recordSourceURL = payload.sourceURL
            recordBaselineKIF = try? exportedKIF()
        } else {
            recordFileName = nil
            recordSourceURL = nil
            recordBaselineKIF = nil
        }
        refreshStoredAnalysis()
    }

    private func handlePositionChange() {
        clearSelection()
        refreshBookMoves()
        if detailPanel == .precedent {
            refreshPrecedentSummary()
        }
        refreshStoredAnalysis()
        if isAnalysisTrackingPosition {
            policyValueEngine.cancelAndClear()
            analyzeCurrentPosition()
        } else {
            analysisEngine.cancelAndClear()
            refreshContextualAnalysis()
        }
    }

    private func observeCompletedAnalysis() {
        analysisEngineCancellable = analysisEngine.$completedSearch
            .compactMap { $0 }
            .sink { [weak self] completed in
                self?.storeCompletedAnalysis(completed)
            }
    }

    private func storeCompletedAnalysis(_ completed: CompletedEngineSearch) {
        guard let target = analysisTargets.removeValue(
            forKey: completed.requestID
        ) else {
            return
        }

        let storedLines = completed.lines.compactMap { line -> StoredAnalysisLine? in
            let reading = commentReadingLabels(
                line.principalVariation,
                sfen: completed.sfen,
                previousMove: target.previousMove
            )
            guard !reading.isEmpty else {
                return nil
            }
            return StoredAnalysisLine(
                rank: line.rank,
                depth: line.depth,
                seldepth: line.seldepth,
                nodes: line.nodes,
                score: line.score,
                reading: reading
            )
        }
        guard !storedLines.isEmpty else {
            return
        }

        target.node.comment = StoredAnalysisCodec.replacingEngineLines(
            in: target.node.comment,
            engineName: completed.engine.commentName,
            version: completed.engine.version,
            with: storedLines
        )
        if let currentNode = record.current as? Node,
           currentNode === target.node,
           explorationMoves.isEmpty
        {
            refreshStoredAnalysis()
            policyValueEngine.cancelAndClear()
        }
    }

    private func commentReadingLabels(
        _ usis: [String],
        sfen: String,
        previousMove: Move?
    ) -> [String] {
        guard let snapshot = Position.fromSFEN(sfen) else {
            return []
        }
        var lastMove = previousMove
        var labels: [String] = []

        for usi in usis {
            guard let move = snapshot.createMoveByUSI(usi) else {
                break
            }
            labels.append(
                kifDisplayText(
                    for: move,
                    previousMove: lastMove,
                    forReadingLine: true,
                    usesKIFPlayerSymbols: true
                )
            )
            guard snapshot.doMove(move) else {
                break
            }
            lastMove = move
        }
        return labels
    }

    private func refreshStoredAnalysis() {
        guard explorationMoves.isEmpty else {
            storedAnalysis = nil
            return
        }
        storedAnalysis = StoredAnalysisCodec.analyses(
            in: record.current.comment
        ).last
    }

    private func refreshContextualAnalysis() {
        guard detailPanel == .analysis,
              !isAnalysisTrackingPosition,
              !analysisEngine.state.isBusy,
              !(analysisEngine.state == .completed && !analysisEngine.lines.isEmpty)
        else {
            policyValueEngine.cancelAndClear()
            return
        }

        refreshStoredAnalysis()
        if storedAnalysis == nil {
            policyValueEngine.analyze(sfen: position.sfen)
        } else {
            policyValueEngine.cancelAndClear()
        }
    }

    private func refreshBookMoves() {
        bookLookupTask?.cancel()
        bookMoves = []
        isLookingUpBook = false
        guard let openingBook else {
            return
        }

        let snapshot = position.clone()
        let expectedSFEN = snapshot.sfen
        let ply = displayedPly + 1
        isLookingUpBook = true
        bookLookupTask = Task {
            do {
                let moves = try await Task.detached(priority: .utility) {
                    try openingBook.moves(for: snapshot, ply: ply)
                }.value
                guard !Task.isCancelled,
                      self.openingBook === openingBook,
                      position.sfen == expectedSFEN,
                      displayedPly + 1 == ply
                else {
                    return
                }
                isLookingUpBook = false
                bookMoves = moves.sorted {
                    let lhsCount = $0.count ?? 0
                    let rhsCount = $1.count ?? 0
                    if lhsCount == rhsCount {
                        return ($0.evaluation ?? Int.min) > ($1.evaluation ?? Int.min)
                    }
                    return lhsCount > rhsCount
                }
            } catch {
                guard !Task.isCancelled,
                      self.openingBook === openingBook,
                      position.sfen == expectedSFEN
                else {
                    return
                }
                isLookingUpBook = false
                bookMoves = []
                presentedError = PresentedError(
                    title: "定跡を検索できません",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func refreshPrecedentSummary() {
        precedentLookupTask?.cancel()
        precedentSummary = nil
        guard let openingReference else {
            precedentState = .idle
            return
        }

        let snapshot = position.clone()
        let expectedSFEN = snapshot.sfen
        precedentState = .lookingUp
        precedentLookupTask = Task {
            do {
                let worker = Task.detached(priority: .utility) {
                    try openingReference.summary(for: snapshot)
                }
                let summary = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled,
                      self.openingReference === openingReference,
                      position.sfen == expectedSFEN
                else {
                    return
                }
                precedentSummary = summary
                precedentState = .loaded
            } catch {
                guard !Task.isCancelled,
                      self.openingReference === openingReference,
                      position.sfen == expectedSFEN
                else {
                    return
                }
                precedentState = .failed(error.localizedDescription)
                presentedError = PresentedError(
                    title: "前例を検索できません",
                    message: error.localizedDescription
                )
            }
        }
    }
}

private enum RecordExportError: LocalizedError {
    case recordMove(Int)
    case currentLine(Int)
    case explorationMove(String)

    var errorDescription: String? {
        switch self {
        case let .recordMove(ply):
            return "保存用の棋譜を\(ply)手目で複製できませんでした。"
        case let .currentLine(ply):
            return "表示中の\(ply)手目を保存用棋譜で選択できませんでした。"
        case let .explorationMove(usi):
            return "一時検討の指し手 \(usi) を保存用棋譜へ追加できませんでした。"
        }
    }
}
