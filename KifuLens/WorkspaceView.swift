import SwiftShogi
import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("KifuLens.boardFlipped") private var isBoardFlipped = false
    @State private var showsLegalInformation = false
    let openRecord: () -> Void
    let saveRecord: () -> Void
    let openBook: () -> Void
    let openReference: () -> Void

    var body: some View {
        GeometryReader { proxy in
            portraitLayout(in: proxy.size)
                .overlay(alignment: .bottom) {
                    if proxy.safeAreaInsets.bottom > 0 {
                        inspectorPageIndicator
                            .frame(
                                height: proxy.safeAreaInsets.bottom,
                                alignment: .top
                            )
                            // 表示領域を狭めず、下端の余白に重ねる。
                            .offset(y: proxy.safeAreaInsets.bottom)
                    }
                }
        }
    }

    private var inspectorPageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(DetailPanel.allCases) { panel in
                Circle()
                    .fill(
                        panel == model.detailPanel
                            ? KifuLensTheme.accent
                            : KifuLensTheme.tertiaryText
                    )
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("パネルのページ位置")
        .accessibilityValue(model.detailPanel.rawValue)
        .accessibilityIdentifier("inspectorPageIndicator")
    }

    private func portraitLayout(in size: CGSize) -> some View {
        let boardWidth = WorkspaceLayoutMetrics.portraitBoardWidth(in: size)

        return VStack(spacing: 0) {
            BoardStage(
                boardWidth: boardWidth,
                isBoardFlipped: $isBoardFlipped,
                openRecord: openRecord,
                saveRecord: saveRecord,
                openBook: openBook,
                openReference: openReference,
                showLegalInformation: {
                    showsLegalInformation = true
                }
            )
                .frame(maxWidth: .infinity)

            InspectorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showsLegalInformation) {
            LegalInformationView()
                .presentationDetents([.medium, .large])
        }
    }
}

struct WorkspaceLayoutMetrics {
    static let playbackControlWidth: CGFloat = 29
    static let playbackPositionWidth: CGFloat = 44
    static let contextActionWidth: CGFloat = 26

    static func portraitBoardWidth(in size: CGSize) -> CGFloat {
        max(1, size.width - 8)
    }

    static var playbackNavigationWidth: CGFloat {
        playbackControlWidth * 6 + playbackPositionWidth
    }
}

private struct BoardStage: View {
    @EnvironmentObject private var model: AppModel
    let boardWidth: CGFloat
    @Binding var isBoardFlipped: Bool
    let openRecord: () -> Void
    let saveRecord: () -> Void
    let openBook: () -> Void
    let openReference: () -> Void
    let showLegalInformation: () -> Void

    var body: some View {
        let handPieceSize = BoardLayoutMetrics.handPieceSize(
            forBoardWidth: boardWidth
        )
        let arrowLayout = AnalysisMoveArrowLayout(
            boardWidth: boardWidth,
            isBoardFlipped: isBoardFlipped
        )

        VStack(spacing: 0) {
            HandRackView(
                color: isBoardFlipped ? .black : .white,
                pieceSize: handPieceSize,
                width: boardWidth,
                isBoardFlipped: isBoardFlipped
            )

            BoardView(isBoardFlipped: isBoardFlipped)
                .frame(
                    width: boardWidth,
                    height: boardWidth * BoardLayoutMetrics.heightRatio
                )
                .padding(4)
                .background(KifuLensTheme.boardFrame)
                .shadow(color: .black.opacity(0.38), radius: 8, y: 3)

            HandRackView(
                color: isBoardFlipped ? .white : .black,
                pieceSize: handPieceSize,
                width: boardWidth,
                isBoardFlipped: isBoardFlipped
            )

            PlaybackControls(
                isBoardFlipped: $isBoardFlipped,
                openRecord: openRecord,
                saveRecord: saveRecord,
                openBook: openBook,
                openReference: openReference,
                showLegalInformation: showLegalInformation
            )
        }
        .frame(width: boardWidth + 8)
        .overlayPreferenceValue(
            AnalysisHandPieceBoundsPreferenceKey.self
        ) { handPieceBounds in
            GeometryReader { proxy in
                AnalysisMoveArrowOverlay(
                    engine: model.analysisEngine,
                    sideToMove: model.position.color,
                    currentPositionSFEN: model.position.sfen,
                    layout: arrowLayout,
                    handCenter: { pieceType, color in
                        guard let anchor = handPieceBounds[
                            AnalysisHandPieceAnchorKey(
                                pieceType: pieceType,
                                color: color
                            )
                        ] else {
                            return nil
                        }
                        let bounds = proxy[anchor]
                        return CGPoint(x: bounds.midX, y: bounds.midY)
                    }
                )
                .frame(
                    width: arrowLayout.overlaySize.width,
                    height: arrowLayout.overlaySize.height,
                    alignment: .topLeading
                )
                .allowsHitTesting(false)
            }
        }
    }
}

private struct PlaybackControls: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isBoardFlipped: Bool
    let openRecord: () -> Void
    let saveRecord: () -> Void
    let openBook: () -> Void
    let openReference: () -> Void
    let showLegalInformation: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PanelContextSummary(
                engine: model.analysisEngine,
                openRecord: openRecord,
                saveRecord: saveRecord,
                openBook: openBook,
                openReference: openReference,
                showLegalInformation: showLegalInformation
            )

            controlButton(
                "盤面を回転",
                icon: "arrow.trianglehead.2.clockwise",
                disabled: false
            ) {
                isBoardFlipped.toggle()
            }
            .accessibilityIdentifier("boardFlipButton")

            controlButton(
                "先頭",
                icon: "backward.end.fill",
                disabled: model.currentPly == 0
                    && model.explorationMoves.isEmpty
            ) {
                model.goto(ply: 0)
            }

            controlButton(
                "10手戻る",
                icon: "chevron.backward.2",
                disabled: model.currentPly == 0
                    && model.explorationMoves.isEmpty
            ) {
                model.goBackTen()
            }

            controlButton(
                "一手戻る",
                icon: "chevron.left",
                disabled: model.currentPly == 0
                    && model.explorationMoves.isEmpty
            ) {
                model.goBack()
            }

            if model.explorationMoves.isEmpty {
                Text("\(model.currentPly)/\(model.record.length)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(KifuLensTheme.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 4)
                    .frame(
                        minWidth: WorkspaceLayoutMetrics.playbackPositionWidth,
                        maxHeight: .infinity
                    )
                    .layoutPriority(2)
                    .accessibilityLabel(
                        "\(model.currentPly)手目、全\(model.record.length)手"
                    )
                    .accessibilityIdentifier("playbackPosition")
            } else {
                Button {
                    model.incorporateExplorationIntoRecord()
                } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "square.and.arrow.down")
                        Text("取込")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(KifuLensTheme.accent)
                    .frame(width: WorkspaceLayoutMetrics.playbackPositionWidth)
                    .frame(maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("一時検討を棋譜に取り込む")
                .accessibilityIdentifier("incorporateExplorationButton")
            }

            controlButton(
                "一手進む",
                icon: "chevron.right",
                disabled: !model.explorationMoves.isEmpty
                    || model.currentPly >= model.record.length
            ) {
                model.goForward()
            }

            controlButton(
                "10手進む",
                icon: "chevron.forward.2",
                disabled: !model.explorationMoves.isEmpty
                    || model.currentPly >= model.record.length
            ) {
                model.goForwardTen()
            }

            controlButton(
                "末尾",
                icon: "forward.end.fill",
                disabled: !model.explorationMoves.isEmpty
                    || model.currentPly >= model.record.length
            ) {
                model.goto(ply: model.record.length)
            }
        }
        .frame(minHeight: 44)
        .background(KifuLensTheme.backgroundRaised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KifuLensTheme.divider)
                .frame(height: 1)
        }
    }

    private func controlButton(
        _ title: String,
        icon: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    disabled
                        ? KifuLensTheme.tertiaryText
                        : KifuLensTheme.primaryText
                )
                .frame(width: WorkspaceLayoutMetrics.playbackControlWidth)
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}

private struct PanelContextSummary: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var engine: LocalAnalysisEngine
    @State private var showsEngineBenchmark = false
    @State private var showsReferenceDownload = false
    let openRecord: () -> Void
    let saveRecord: () -> Void
    let openBook: () -> Void
    let openReference: () -> Void
    let showLegalInformation: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(primaryText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(KifuLensTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier(primaryIdentifier)

                if let secondaryText {
                    Text(secondaryText)
                        .font(.system(size: 8.5))
                        .foregroundStyle(KifuLensTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .accessibilityIdentifier(secondaryIdentifier)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            contextActions
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .sheet(isPresented: $showsEngineBenchmark) {
            EngineBenchmarkView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showsReferenceDownload) {
            OpeningReferenceDownloadView()
                .environmentObject(model)
        }
    }

    private var primaryText: String {
        switch model.detailPanel {
        case .settings:
            return "解析設定"
        case .record:
            return model.recordTitle
        case .analysis:
            return engine.displayName
        case .book:
            return model.openingBookSummary?.fileName ?? "定跡未選択"
        case .precedent:
            if model.precedentState == .opening {
                return "Floodgate前例準備中"
            }
            return model.openingReference?.fileName ?? "Floodgate前例未選択"
        }
    }

    private var secondaryText: String? {
        switch model.detailPanel {
        case .settings:
            let settings = model.analysisSettings
            let engine = AnalysisEngineCatalog.descriptor(
                for: settings.engineIdentifier
            )?.displayName ?? "端末内エンジン"
            return "\(engine)・\(settings.threadCount) Thread・"
                + "Hash \(settings.hashSizeMB) MB・"
                + settings.timeLimit.displayText
        case .record:
            return model.explorationMoves.isEmpty ? nil : "一時検討"
        case .analysis:
            if let completionText = engine.completionText {
                return completionText
            }
            switch engine.state {
            case .starting: return "準備中"
            case .analyzing: return "解析中"
            case .stopping: return "停止中"
            case .benchmarking: return "ベンチマーク中"
            case .failed: return "利用不可"
            default: return nil
            }
        case .book:
            return model.openingBookSummary?.sizeText
        case .precedent:
            return model.openingReference?.sizeText
        }
    }

    private var primaryIdentifier: String {
        model.detailPanel == .analysis && engine.completionText == nil
            ? "analysisEngineSubtitle"
            : "panelContextPrimary"
    }

    private var secondaryIdentifier: String {
        model.detailPanel == .analysis && engine.completionText != nil
            ? "analysisCompletionLabel"
            : "panelContextSecondary"
    }

    @ViewBuilder
    private var contextActions: some View {
        HStack(spacing: 2) {
            switch model.detailPanel {
            case .settings:
                contextActionButton(
                    title: "ベンチマーク",
                    icon: "gauge.with.dots.needle.50percent",
                    identifier: "engineBenchmarkButton",
                    action: {
                        showsEngineBenchmark = true
                    }
                )
            case .record:
                contextActionButton(
                    title: "情報",
                    icon: "info.circle",
                    identifier: "legalInformationButton",
                    action: showLegalInformation
                )
                contextActionButton(
                    title: "保存",
                    icon: "",
                    identifier: "recordSaveButton",
                    usesFloppyIcon: true,
                    action: saveRecord
                )
                contextActionButton(
                    title: "読込",
                    icon: "tray.and.arrow.down.fill",
                    identifier: "recordImportButton",
                    action: openRecord
                )
            case .analysis:
                analysisButton
            case .book:
                contextActionButton(
                    title: "定跡を開く",
                    icon: "folder",
                    identifier: "bookImportButton",
                    isBusy: model.isOpeningBook,
                    action: openBook
                )
            case .precedent:
                contextActionButton(
                    title: "前例DBをダウンロード",
                    icon: "arrow.down.circle",
                    identifier: "precedentDownloadButton",
                    action: { showsReferenceDownload = true }
                )
                .disabled(model.precedentState == .opening)
                contextActionButton(
                    title: "前例集を開く",
                    icon: "folder",
                    identifier: "precedentImportButton",
                    isBusy: model.precedentState == .opening,
                    action: openReference
                )
            }
        }
    }

    private func contextActionButton(
        title: String,
        icon: String,
        identifier: String,
        isBusy: Bool = false,
        usesFloppyIcon: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else if usesFloppyIcon {
                    FloppyDiskIcon()
                } else {
                    Image(systemName: icon)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(KifuLensTheme.primaryText)
            .frame(
                width: WorkspaceLayoutMetrics.contextActionWidth,
                height: 26
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var analysisButton: some View {
        Button(action: analysisAction) {
            HStack(spacing: 4) {
                if engine.state == .starting || engine.state == .stopping {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(KifuLensTheme.background)
                } else {
                    Image(
                        systemName: model.isAnalysisTrackingPosition
                            ? "stop.fill"
                            : "play.fill"
                    )
                }
                Text(analysisActionTitle)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(KifuLensTheme.background)
            .padding(.horizontal, 5)
            .frame(minWidth: 52, minHeight: 26)
            .background(
                model.isAnalysisTrackingPosition
                    ? KifuLensTheme.negative
                    : KifuLensTheme.accent
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canPerformAnalysisAction)
        .opacity(canPerformAnalysisAction ? 1 : 0.65)
        .accessibilityLabel(
            model.isAnalysisTrackingPosition ? "解析追従停止" : "解析開始"
        )
        .accessibilityIdentifier("analysisStartStopButton")
    }

    private var analysisActionTitle: String {
        switch engine.state {
        case .starting: return "準備中"
        case .analyzing: return "停止"
        case .stopping: return "停止中"
        case .benchmarking: return "ベンチマーク中"
        case .failed: return "利用不可"
        case .completed where model.isAnalysisTrackingPosition: return "終了"
        default: return "開始"
        }
    }

    private var canPerformAnalysisAction: Bool {
        switch engine.state {
        case .starting, .stopping, .benchmarking, .failed:
            return false
        default:
            return true
        }
    }

    private func analysisAction() {
        if model.isAnalysisTrackingPosition {
            model.stopAnalysis()
        } else {
            model.runAnalysis()
        }
    }
}

private struct FloppyDiskIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .stroke(lineWidth: 1.2)

            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                    .stroke(lineWidth: 0.9)
                    .frame(width: 8, height: 4)

                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                    .fill(.primary)
                    .frame(width: 6, height: 3)
            }
        }
        .frame(width: 13, height: 13)
    }
}
