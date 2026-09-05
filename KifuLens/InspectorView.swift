import AuthenticationServices
import SwiftShogi
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.detailPanel) {
            AnalysisSettingsPanel()
                .tag(DetailPanel.settings)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

            RecordPanel()
                .tag(DetailPanel.record)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

            AnalysisPanel()
                .tag(DetailPanel.analysis)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

            OpeningBookPanel()
                .tag(DetailPanel.book)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

            PrecedentPanel()
                .tag(DetailPanel.precedent)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .accessibilityIdentifier("inspectorPager")
        .clipped()
        .background(KifuLensTheme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KifuLensTheme.divider)
                .frame(height: 1)
        }
    }
}

private struct AnalysisSettingsPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var engineIdentifier = AnalysisSettings.default.engineIdentifier
    @State private var threadCount = AnalysisSettings.default.threadCount
    @State private var hashSizeMB = AnalysisSettings.default.hashSizeMB
    @State private var timeLimit = AnalysisSettings.default.timeLimit
    @State private var isSaving = false
    @State private var notice: AnalysisSettingsNotice?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                settingCell(title: "エンジン") {
                    Menu {
                        ForEach(AnalysisEngineCatalog.installedEngines) { engine in
                            Button {
                                engineIdentifier = engine.id
                            } label: {
                                if engine.id == engineIdentifier {
                                    Label(engine.displayName, systemImage: "checkmark")
                                } else {
                                    Text(engine.displayName)
                                }
                            }
                            .accessibilityIdentifier("engineChoice-\(engine.id.rawValue)")
                        }
                    } label: {
                        compactMenuLabel(selectedEngineName)
                    }
                    .accessibilityLabel(selectedEngineName)
                    .accessibilityIdentifier("analysisEngineMenu")
                }

                settingCell(title: "スレッド") {
                    settingMenu(
                        selection: $threadCount,
                        options: AnalysisSettingsOptions.threadCounts,
                        displayText: String.init
                    )
                }
            }

            HStack(spacing: 4) {
                settingCell(title: "Hash") {
                    settingMenu(
                        selection: $hashSizeMB,
                        options: AnalysisSettingsOptions.hashSizesMB,
                        displayText: { "\($0) MB" }
                    )
                }

                settingCell(title: "解析時間") {
                    settingMenu(
                        selection: $timeLimit,
                        options: AnalysisSettingsOptions.timeLimits,
                        displayText: \.displayText
                    )
                }
            }

            actionRow
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .onAppear(perform: load)
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("閉じる"))
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 4) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = []
            } onCompletion: { _ in
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(true)
            .opacity(0.42)
            .accessibilityHint("現在は利用できません")
            .accessibilityIdentifier(
                "analysisSettingsAppleSignInButton"
            )

            Button {
                save()
            } label: {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text("設定を適用")
                        .lineLimit(1)
                }
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent)
            .tint(KifuLensTheme.accent)
            .disabled(
                isSaving
                    || model.isAnalysisTrackingPosition
                    || model.analysisEngine.state.isBusy
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("analysisSettingsSaveButton")
        }
    }

    private func settingCell<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(KifuLensTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            content()
                .tint(KifuLensTheme.accent)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(KifuLensTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func settingMenu<Value: Hashable>(
        selection: Binding<Value>,
        options: [Value],
        displayText: @escaping (Value) -> String
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if option == selection.wrappedValue {
                        Label(displayText(option), systemImage: "checkmark")
                    } else {
                        Text(displayText(option))
                    }
                }
            }
        } label: {
            compactMenuLabel(displayText(selection.wrappedValue))
        }
        .accessibilityLabel(displayText(selection.wrappedValue))
    }

    private func compactMenuLabel(_ text: String) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .fixedSize()
        }
    }

    private func load() {
        let settings = model.analysisSettings
        engineIdentifier = settings.engineIdentifier
        threadCount = settings.threadCount
        hashSizeMB = settings.hashSizeMB
        timeLimit = settings.timeLimit
    }

    private var selectedEngineName: String {
        AnalysisEngineCatalog.descriptor(for: engineIdentifier)?.displayName
            ?? AnalysisEngineCatalog.installedEngines[0].displayName
    }

    private func save() {
        let settings = AnalysisSettings(
            engineIdentifier: engineIdentifier,
            threadCount: threadCount,
            hashSizeMB: hashSizeMB,
            timeLimit: timeLimit
        )
        isSaving = true
        Task {
            let didApply = await model.applyAnalysisSettings(settings)
            isSaving = false
            if didApply {
                notice = .applied
            }
        }
    }
}

private enum AnalysisSettingsNotice: Identifiable {
    case applied

    var id: String {
        switch self {
        case .applied:
            return "applied"
        }
    }

    var title: String {
        switch self {
        case .applied:
            return "解析設定を反映しました"
        }
    }

    var message: String {
        switch self {
        case .applied:
            return "設定内容を端末内解析へ反映しました。"
        }
    }
}

private struct RecordPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.moveNodes.isEmpty {
                CompactEmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "棋譜を開いて検討を始める",
                    message: "KIF・KI2・CSA・SFEN・USIに対応",
                    buttonTitle: nil,
                    action: {}
                )
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            Button {
                                model.goto(ply: 0)
                            } label: {
                                MoveRow(
                                    number: 0,
                                    text: "開始局面",
                                    selected: model.currentPly == 0 && model.explorationMoves.isEmpty
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recordStartPosition")
                            .accessibilityAddTraits(
                                model.currentPly == 0 && model.explorationMoves.isEmpty
                                    ? .isSelected
                                    : []
                            )
                            .id(0)

                            ForEach(model.moveNodes, id: \.ply) { node in
                                Button {
                                    model.goto(ply: node.ply)
                                } label: {
                                    MoveRow(
                                        number: node.ply,
                                        text: model.displayText(for: node),
                                        selected: model.currentPly == node.ply && model.explorationMoves.isEmpty
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("recordMove\(node.ply)")
                                .accessibilityAddTraits(
                                    model.currentPly == node.ply && model.explorationMoves.isEmpty
                                        ? .isSelected
                                        : []
                                )
                                .id(node.ply)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: model.currentPly) { _, value in
                        withAnimation(.easeOut(duration: 0.2)) {
                            reader.scrollTo(value, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

private struct MoveRow: View {
    let number: Int
    let text: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(number == 0 ? "—" : "\(number)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(selected ? KifuLensTheme.accent : KifuLensTheme.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 20, alignment: .trailing)

            Text(text)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(KifuLensTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(minHeight: 30)
        .background(selected ? KifuLensTheme.surfaceSelected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            if selected {
                Rectangle()
                    .fill(KifuLensTheme.accent)
                    .frame(width: 3)
            }
        }
    }
}

private struct AnalysisPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AnalysisPanelContent(
            engine: model.analysisEngine,
            policy: model.policyValueEngine
        )
            .environmentObject(model)
    }
}

struct AnalysisLayoutMetrics {
    static let candidateCount = 3

    static func candidateMinimumHeight(in availableHeight: CGFloat) -> CGFloat {
        max(0, availableHeight / CGFloat(candidateCount))
    }

    static func principalVariationLineLimit(
        forCandidateHeight candidateHeight: CGFloat
    ) -> Int {
        if candidateHeight >= 72 {
            return 3
        }
        if candidateHeight >= 50 {
            return 2
        }
        return 1
    }
}

private struct AnalysisPanelContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var engine: LocalAnalysisEngine
    @ObservedObject var policy: PolicyValueEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsLiveAnalysis {
                EngineMetricsRow(metrics: engine.metrics)
            }

            if case let .failed(message) = engine.state {
                CompactEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "端末内エンジンを起動できません",
                    message: message,
                    buttonTitle: nil,
                    action: {}
                )
            } else if engine.state == .starting {
                CompactLoadingState(
                    title: "\(engine.displayName)を準備中",
                    message: "評価関数と進行度係数を端末内で読み込んでいます"
                )
            } else if engine.lines.isEmpty, engine.state.isSearching {
                CompactLoadingState(
                    title: engine.state == .stopping ? "解析を停止中" : "候補手を探索中",
                    message: "通信せず、\(engine.displayName)がこの端末だけで解析しています"
                )
            } else if showsLiveAnalysis {
                liveAnalysisLines
            } else if let stored = model.storedAnalysis {
                storedAnalysisLines(stored)
            } else {
                policyValueContent
            }
        }
    }

    private var showsLiveAnalysis: Bool {
        engine.state.isSearching
            || (engine.state == .completed && !engine.lines.isEmpty)
    }

    private var liveAnalysisLines: some View {
        GeometryReader { proxy in
            let candidateMinimumHeight =
                AnalysisLayoutMetrics.candidateMinimumHeight(
                    in: proxy.size.height
                )

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(engine.lines) { line in
                        Button {
                            model.applyAnalysisLine(line)
                        } label: {
                            EngineCandidateRow(
                                line: line,
                                displayMove: line.principalVariation.first.map {
                                    model.displayText(
                                        forUSI: $0,
                                        forReadingLine: true
                                    )
                                } ?? "候補手なし",
                                continuation: line.principalVariation.count > 1
                                    ? model.principalVariationLabels(
                                        line.principalVariation,
                                        droppingFirst: 1
                                    )
                                    : [],
                                minimumHeight: candidateMinimumHeight,
                                principalVariationLineLimit:
                                    AnalysisLayoutMetrics
                                        .principalVariationLineLimit(
                                            forCandidateHeight:
                                                candidateMinimumHeight
                                        ),
                                metadataText: nil
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("analysisLine\(line.rank)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func storedAnalysisLines(
        _ stored: StoredAnalysis
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(stored.engineName) \(stored.version)・保存済み解析")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(KifuLensTheme.secondaryText)
                .lineLimit(1)
                .accessibilityIdentifier("storedAnalysisHeader")

            GeometryReader { proxy in
                let minimumHeight = AnalysisLayoutMetrics
                    .candidateMinimumHeight(in: proxy.size.height)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(stored.lines) { line in
                            EngineCandidateRow(
                                line: EngineAnalysisLine(
                                    rank: line.rank,
                                    score: line.score,
                                    principalVariation: [],
                                    depth: line.depth,
                                    seldepth: line.seldepth,
                                    nodes: line.nodes,
                                    nps: 0,
                                    timeMilliseconds: 0,
                                    hashfull: 0
                                ),
                                displayMove: line.reading.first ?? "候補手なし",
                                continuation: Array(line.reading.dropFirst()),
                                minimumHeight: minimumHeight,
                                principalVariationLineLimit:
                                    AnalysisLayoutMetrics
                                        .principalVariationLineLimit(
                                            forCandidateHeight: minimumHeight
                                        ),
                                metadataText:
                                    "d\(line.depth)/\(line.seldepth) "
                                    + EngineMetricFormatting.compactCount(line.nodes)
                            )
                            .accessibilityIdentifier(
                                "storedAnalysisLine\(line.rank)"
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var policyValueContent: some View {
        switch policy.state {
        case .idle, .loading:
            CompactLoadingState(
                title: "DL水匠の推定選択率を計算中",
                message: "解析開始前にpolicy/valueを端末内で推論しています"
            )
        case let .failed(message):
            CompactEmptyState(
                icon: "exclamationmark.triangle",
                title: "推定選択率を表示できません",
                message: message,
                buttonTitle: nil,
                action: {}
            )
        case .ready:
            if let result = policy.result {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("DL水匠・推定選択率")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(KifuLensTheme.secondaryText)
                        Spacer(minLength: 0)
                        Text(
                            String(
                                format: "手番側勝率 %.1f%%",
                                min(max(result.sideToMoveWinRate, 0), 1) * 100
                            )
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(KifuLensTheme.secondaryText)
                    }
                    .accessibilityIdentifier("policyValueHeader")

                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(result.moves) { move in
                                Button {
                                    model.applyBookMove(
                                        OpeningBookMove(usi: move.usi)
                                    )
                                } label: {
                                    PolicyCandidateRow(
                                        move: move,
                                        displayMove: model.displayText(
                                            forUSI: move.usi,
                                            forReadingLine: true
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(
                                    "policyValueLine\(move.rank)"
                                )
                            }
                        }
                    }
                    .accessibilityIdentifier("policyValueCandidateList")
                    .scrollIndicators(.hidden)
                }
            }
        }
    }
}

private struct OpeningBookPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.openingBook == nil {
                CompactEmptyState(
                    icon: "books.vertical",
                    title: "巨大定跡をオンデマンド参照",
                    message: "全件をメモリに載せず、表示中の局面だけ検索します",
                    buttonTitle: nil,
                    action: {}
                )
            } else if model.isLookingUpBook {
                CompactLoadingState(
                    title: "現在局面の定跡を検索中",
                    message: "巨大ファイルも全件をメモリに載せず照合します"
                )
            } else if model.bookMoves.isEmpty {
                CompactEmptyState(
                    icon: "text.magnifyingglass",
                    title: "この局面に候補手はありません",
                    message: "棋譜を前後すると自動で再検索します",
                    buttonTitle: nil,
                    action: {}
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(model.bookMoves.enumerated()), id: \.element.id) { index, move in
                            Button {
                                model.applyBookMove(move)
                            } label: {
                                BookMoveRow(
                                    rank: index + 1,
                                    displayMove: model.displayText(forUSI: move.usi),
                                    move: move,
                                    sideToMoveIsBlack: model.position.color == .black
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct PrecedentPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.precedentState == .opening {
                CompactLoadingState(
                    title: "前例集を開いています",
                    message: "同梱版は初回のみ端末内へ準備します"
                )
            } else if model.openingReference == nil {
                CompactEmptyState(
                    icon: "archivebox",
                    title: "Floodgate前例集を開いてください",
                    message: "Files（Google Drive等）から選択・複数可",
                    buttonTitle: nil,
                    action: {}
                )
            } else {
                switch model.precedentState {
                case .opening:
                    EmptyView()
                case .lookingUp:
                    CompactLoadingState(
                        title: "現在局面の前例を検索中",
                        message: "棋譜を前後すると自動で再検索します"
                    )
                case let .failed(message):
                    CompactEmptyState(
                        icon: "exclamationmark.triangle",
                        title: "前例を検索できません",
                        message: message,
                        buttonTitle: nil,
                        action: {}
                    )
                case .idle, .loaded:
                    precedentContent
                }
            }
        }
        .accessibilityIdentifier("precedentPanel")
    }

    @ViewBuilder
    private var precedentContent: some View {
        if let summary = model.precedentSummary {
            if summary.occurrenceCount == 0 {
                CompactEmptyState(
                    icon: "text.magnifyingglass",
                    title: "この局面に前例はありません",
                    message: "棋譜を前後すると自動で再検索します",
                    buttonTitle: nil,
                    action: {}
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        HStack {
                            Text("前例 \(summary.occurrenceCount.formatted())局")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KifuLensTheme.primaryText)
                            Spacer(minLength: 0)
                            Text("選択率・勝敗")
                                .font(.system(size: 8.5))
                                .foregroundStyle(KifuLensTheme.tertiaryText)
                        }
                        .padding(.horizontal, 5)

                        ForEach(
                            Array(summary.moves.enumerated()),
                            id: \.element.id
                        ) { index, move in
                            PrecedentMoveRow(
                                rank: index + 1,
                                move: move,
                                totalCount: summary.occurrenceCount,
                                fallbackDisplayText: model.displayText(
                                    forUSI: move.usi
                                )
                            )
                        }

                        if !summary.examples.isEmpty {
                            Text("代表対局")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KifuLensTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 5)
                                .padding(.top, 3)

                            ForEach(summary.examples) { example in
                                PrecedentExampleRow(example: example)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        } else {
            CompactLoadingState(
                title: "現在局面の前例を検索中",
                message: "棋譜を前後すると自動で再検索します"
            )
        }
    }
}

private struct PrecedentMoveRow: View {
    let rank: Int
    let move: PrecedentMove
    let totalCount: Int
    let fallbackDisplayText: String

    var body: some View {
        HStack(spacing: 6) {
            RankIndicator(rank: rank)

            Text(move.displayText.isEmpty ? fallbackDisplayText : move.displayText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KifuLensTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(selectionRateText)  \(move.count.formatted())局")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(KifuLensTheme.primaryText)
                    .lineLimit(1)
                Text(
                    "先\(move.blackWinCount)・後\(move.whiteWinCount)・"
                        + "引\(move.drawCount)・不\(move.unknownCount)"
                )
                .font(.system(size: 8.5).monospacedDigit())
                .foregroundStyle(KifuLensTheme.secondaryText)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 5)
        .frame(minHeight: 34)
        .background(KifuLensTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(KifuLensTheme.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("precedentMove\(rank)")
    }

    private var selectionRateText: String {
        guard totalCount > 0 else {
            return "—"
        }
        return String(
            format: "%.1f%%",
            Double(move.count) * 100 / Double(totalCount)
        )
    }
}

private struct PrecedentExampleRow: View {
    let example: PrecedentExample

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("▲\(example.blackName)  △\(example.whiteName)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(KifuLensTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(example.outcome.title)
                    .font(.system(size: 8.5))
                    .foregroundStyle(KifuLensTheme.secondaryText)
                    .lineLimit(1)
            }
            Text(
                "\(example.ply)手目 \(example.nextMoveText)・\(example.dateText)"
            )
            .font(.system(size: 8.5))
            .foregroundStyle(KifuLensTheme.secondaryText)
            .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(KifuLensTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct EngineMetricsRow: View {
    let metrics: EngineSearchMetrics

    var body: some View {
        GeometryReader { proxy in
            let metricWidth = max(0, (proxy.size.width - 4) / 5)

            HStack(spacing: 0) {
                metric(
                    "Time",
                    value: timeText,
                    identifier: "engineMetricTime",
                    width: metricWidth
                )
                divider
                metric(
                    "Hash",
                    value: String(format: "%.1f%%", Double(metrics.hashfull) / 10),
                    identifier: "engineMetricHash",
                    width: metricWidth
                )
                divider
                metric(
                    "Depth",
                    value: "\(metrics.depth)/\(metrics.seldepth)",
                    identifier: "engineMetricDepth",
                    width: metricWidth
                )
                divider
                metric(
                    "Nodes",
                    value: EngineMetricFormatting.compactCount(metrics.nodes),
                    identifier: "engineMetricNodes",
                    width: metricWidth,
                    fontSize: 10
                )
                divider
                metric(
                    "NPS",
                    value: EngineMetricFormatting.compactCount(metrics.nps),
                    identifier: "engineMetricNPS",
                    width: metricWidth,
                    fontSize: 10
                )
            }
        }
        .frame(height: 17)
        .padding(.vertical, 1)
    }

    private var divider: some View {
        Rectangle()
            .fill(KifuLensTheme.divider)
            .frame(width: 1, height: 15)
    }

    private func metric(
        _ title: String,
        value: String,
        identifier: String,
        width: CGFloat,
        fontSize: CGFloat = 9
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(title):")
                .foregroundStyle(KifuLensTheme.tertiaryText)
            Text(value)
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(KifuLensTheme.primaryText)
        }
        .font(.system(size: fontSize))
        .lineLimit(1)
        .minimumScaleFactor(fontSize > 9 ? 0.85 : 0.55)
        .frame(width: width, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityIdentifier(identifier)
    }

    private var timeText: String {
        if metrics.timeMilliseconds < 1_000 {
            return "\(metrics.timeMilliseconds)ms"
        }
        return String(format: "%.1fs", Double(metrics.timeMilliseconds) / 1_000)
    }

}

enum EngineMetricFormatting {
    static func compactCount(_ value: UInt64) -> String {
        if value == 0 {
            return "0"
        }
        if value >= 999_500_000 {
            return threeSignificantDigits(Double(value) / 1_000_000_000) + "B"
        }
        if value >= 999_500 {
            return threeSignificantDigits(Double(value) / 1_000_000) + "M"
        }
        if value >= 1_000 {
            return threeSignificantDigits(Double(value) / 1_000) + "k"
        }
        return threeSignificantDigits(Double(value))
    }

    private static func threeSignificantDigits(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }
}

private struct EngineCandidateRow: View {
    let line: EngineAnalysisLine
    let displayMove: String
    let continuation: [String]
    let minimumHeight: CGFloat
    let principalVariationLineLimit: Int
    let metadataText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                RankIndicator(rank: line.rank)

                EngineScoreLabel(score: line.score)
                    .frame(width: 44, alignment: .leading)

                Text(displayMove)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KifuLensTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)

                if let metadataText {
                    Text(metadataText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(KifuLensTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if !continuation.isEmpty {
                AdaptivePrincipalVariationLine(
                    moves: continuation,
                    lineLimit: principalVariationLineLimit
                )
                    .accessibilityIdentifier(
                        "analysisPrincipalVariation\(line.rank)"
                    )
            }
        }
        .padding(.horizontal, 3)
        .frame(
            maxWidth: .infinity,
            minHeight: minimumHeight,
            alignment: .leading
        )
        .background(
            line.rank == 1
                ? KifuLensTheme.surfaceSelected.opacity(0.7)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KifuLensTheme.divider)
                .frame(height: 1)
        }
    }
}

private struct PolicyCandidateRow: View {
    let move: PolicyValueMove
    let displayMove: String

    private var probabilityFillFraction: CGFloat {
        CGFloat(min(max(move.probability / 0.8, 0), 1))
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(move.rank)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(KifuLensTheme.secondaryText)
                .frame(width: 18, height: 18)
                .background(KifuLensTheme.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(displayMove)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KifuLensTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(String(format: "%.1f%%", move.probability * 100))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(KifuLensTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    KifuLensTheme.surfaceRaised
                    Rectangle()
                        .fill(Color.blue.opacity(0.30))
                        .frame(
                            width: geometry.size.width
                                * probabilityFillFraction
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(KifuLensTheme.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AdaptivePrincipalVariationLine: View {
    let moves: [String]
    let lineLimit: Int

    var body: some View {
        Text(AnalysisReadingLineFormatting.nonBreakingText(for: moves))
        .font(.caption2)
        .foregroundStyle(KifuLensTheme.secondaryText)
        .lineLimit(lineLimit)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moves.joined(separator: "  "))
    }
}

struct AnalysisReadingLineFormatting {
    private static let wordJoiner = "\u{2060}"

    static func nonBreakingText(for moves: [String]) -> String {
        moves.map { move in
            move.map(String.init).joined(separator: wordJoiner)
        }
        .joined(separator: "  ")
    }
}

private struct EngineScoreLabel: View {
    let score: EngineScore?

    var body: some View {
        Text(scoreText)
            .font(.subheadline.monospacedDigit().weight(.bold))
            .foregroundStyle(scoreColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .accessibilityLabel(score?.accessibilityText ?? "評価値なし")
    }

    private var scoreText: String {
        score?.displayText ?? "—"
    }

    private var scoreColor: SwiftUI.Color {
        guard let score else {
            return KifuLensTheme.secondaryText
        }
        switch score {
        case let .centipawn(value):
            return evaluationColor(for: evaluationScoreTone(value))
        case let .mate(sign, _):
            return sign >= 0 ? KifuLensTheme.positive : KifuLensTheme.negative
        }
    }
}

private struct CandidateRow: View {
    let rank: Int
    let move: String
    let usi: String
    let score: Int
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            RankIndicator(rank: rank)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(move)
                        .font(.headline)
                        .foregroundStyle(KifuLensTheme.primaryText)
                    Text(usi)
                        .font(.caption2.monospaced())
                        .foregroundStyle(KifuLensTheme.tertiaryText)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(KifuLensTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            ScoreLabel(score: score)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 51)
        .background(KifuLensTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(KifuLensTheme.divider, lineWidth: 1)
        }
    }
}

private struct BookMoveRow: View {
    let rank: Int
    let displayMove: String
    let move: OpeningBookMove
    let sideToMoveIsBlack: Bool

    var body: some View {
        HStack(spacing: 6) {
            RankIndicator(rank: rank)

            Text(displayMove)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KifuLensTheme.primaryText)
                .lineLimit(1)

            HStack(spacing: 5) {
                if let depth = move.depth {
                    Text("depth \(depth)")
                }
                if let count = move.count {
                    Text("count \(count.formatted())")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(KifuLensTheme.secondaryText)
            .lineLimit(1)

            Spacer(minLength: 0)

            if let evaluation = move.evaluation {
                ScoreLabel(
                    score: openingBookEvaluationFromBlackPerspective(
                        evaluation,
                        sideToMoveIsBlack: sideToMoveIsBlack
                    )
                )
            }
        }
        .padding(.horizontal, 5)
        .frame(minHeight: 30)
        .background(KifuLensTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(KifuLensTheme.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bookMove\(rank)")
    }
}

private struct CompactLoadingState: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .tint(KifuLensTheme.accent)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KifuLensTheme.primaryText)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(KifuLensTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(4)
        .background(KifuLensTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct CompactEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KifuLensTheme.accent)
                .frame(width: 26, height: 26)
                .background(KifuLensTheme.accentSoft.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KifuLensTheme.primaryText)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(KifuLensTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KifuLensTheme.accent)
            }
        }
        .padding(4)
        .background(KifuLensTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct RankIndicator: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(rank == 1 ? KifuLensTheme.background : KifuLensTheme.secondaryText)
            .frame(width: 20, height: 20)
            .background(rank == 1 ? KifuLensTheme.accent : KifuLensTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct ScoreLabel: View {
    let score: Int

    var body: some View {
        let color = evaluationColor(for: evaluationScoreTone(score))
        Text(scoreText(score))
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 22)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct InfoChip: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(KifuLensTheme.secondaryText)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(KifuLensTheme.backgroundRaised)
            .clipShape(Capsule())
    }
}

private func scoreText(_ score: Int) -> String {
    openingBookEvaluationText(score)
}

func openingBookEvaluationText(_ score: Int) -> String {
    score >= 0 ? "+\(score)" : "\(score)"
}

enum EvaluationScoreTone: Equatable {
    case blackAdvantage
    case equal
    case whiteAdvantage
}

func evaluationScoreTone(_ score: Int) -> EvaluationScoreTone {
    if score >= 200 {
        return .blackAdvantage
    }
    if score <= -200 {
        return .whiteAdvantage
    }
    return .equal
}

func openingBookEvaluationFromBlackPerspective(
    _ score: Int,
    sideToMoveIsBlack: Bool
) -> Int {
    sideToMoveIsBlack ? score : -score
}

private func evaluationColor(for tone: EvaluationScoreTone) -> SwiftUI.Color {
    switch tone {
    case .blackAdvantage:
        return KifuLensTheme.positive
    case .equal:
        return KifuLensTheme.neutral
    case .whiteAdvantage:
        return KifuLensTheme.negative
    }
}

private extension DetailPanel {
    var iconName: String {
        switch self {
        case .settings: return "gearshape"
        case .record: return "list.number"
        case .analysis: return "waveform.path.ecg"
        case .book: return "books.vertical"
        case .precedent: return "archivebox"
        }
    }
}
