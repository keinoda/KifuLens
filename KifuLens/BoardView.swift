import SwiftShogi
import SwiftUI
import UIKit

enum BoardLayoutMetrics {
    static let coordinateGutter: CGFloat = 12
    static let heightRatio: CGFloat = 1.10
    static let handPieceScale: CGFloat = 0.85
    static let boardFrameInset: CGFloat = 4

    static func cellSize(forBoardWidth boardWidth: CGFloat) -> CGSize {
        CGSize(
            width: max(1, (boardWidth - coordinateGutter) / 9),
            height: max(1, (boardWidth * heightRatio - coordinateGutter) / 9)
        )
    }

    static func handPieceSize(forBoardWidth boardWidth: CGFloat) -> CGSize {
        let cellSize = cellSize(forBoardWidth: boardWidth)
        return CGSize(
            width: cellSize.width * handPieceScale,
            height: cellSize.height * handPieceScale
        )
    }

    static func handRackHeight(forBoardWidth boardWidth: CGFloat) -> CGFloat {
        max(34, handPieceSize(forBoardWidth: boardWidth).height + 2)
    }

    static func square(
        at location: CGPoint,
        in size: CGSize,
        isBoardFlipped: Bool = false
    ) -> Square? {
        let boardWidth = size.width - coordinateGutter
        let boardHeight = size.height - coordinateGutter
        let boardOrigin = CGPoint(
            x: isBoardFlipped ? coordinateGutter : 0,
            y: isBoardFlipped ? 0 : coordinateGutter
        )
        guard boardWidth > 0,
              boardHeight > 0,
              location.x >= boardOrigin.x,
              location.x < boardOrigin.x + boardWidth,
              location.y >= boardOrigin.y,
              location.y < boardOrigin.y + boardHeight
        else {
            return nil
        }

        let fileIndex = Int(
            (location.x - boardOrigin.x) / (boardWidth / 9)
        )
        let rankIndex = Int(
            (location.y - boardOrigin.y) / (boardHeight / 9)
        )
        if isBoardFlipped {
            return Square(file: fileIndex + 1, rank: 9 - rankIndex)
        }
        return Square.fromXY(x: fileIndex, y: rankIndex)
    }
}

enum AnalysisMoveArrowSource: Equatable {
    case square(Square)
    case hand(PieceType, SwiftShogi.Color)
}

struct AnalysisMoveArrowModel: Equatable {
    let source: AnalysisMoveArrowSource
    let destination: Square

    init?(usiMove: String, color: SwiftShogi.Color) {
        guard let parsedMove = parseUSIMove(
            usiMove.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return nil
        }

        switch parsedMove.from {
        case let .left(square):
            source = .square(square)
        case let .right(pieceType):
            source = .hand(pieceType, color)
        }
        destination = parsedMove.to
    }

    static func bestMove(
        state: LocalAnalysisState,
        lines: [EngineAnalysisLine],
        sideToMove: SwiftShogi.Color,
        completedSearchSFEN: String?,
        currentPositionSFEN: String
    ) -> AnalysisMoveArrowModel? {
        let showsCompletedSearch = state == .completed
            && completedSearchSFEN == currentPositionSFEN
        guard state.isSearching || showsCompletedSearch,
              let usiMove = lines.first(where: { $0.rank == 1 })?
                .principalVariation.first
        else {
            return nil
        }
        return AnalysisMoveArrowModel(
            usiMove: usiMove,
            color: sideToMove
        )
    }
}

struct AnalysisHandPieceAnchorKey: Hashable {
    let pieceType: PieceType
    let color: SwiftShogi.Color
}

struct AnalysisHandPieceBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [AnalysisHandPieceAnchorKey: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [AnalysisHandPieceAnchorKey: Anchor<CGRect>],
        nextValue: () -> [AnalysisHandPieceAnchorKey: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct AnalysisMoveArrowLayout: Equatable {
    let boardWidth: CGFloat
    let isBoardFlipped: Bool

    private var boardHeight: CGFloat {
        boardWidth * BoardLayoutMetrics.heightRatio
    }

    private var boardCellSize: CGSize {
        BoardLayoutMetrics.cellSize(forBoardWidth: boardWidth)
    }

    private var handRackHeight: CGFloat {
        BoardLayoutMetrics.handRackHeight(forBoardWidth: boardWidth)
    }

    var overlaySize: CGSize {
        CGSize(
            width: boardWidth + BoardLayoutMetrics.boardFrameInset * 2,
            height: handRackHeight * 2
                + boardHeight
                + BoardLayoutMetrics.boardFrameInset * 2
        )
    }

    func squareCenter(_ square: Square) -> CGPoint {
        let gutter = BoardLayoutMetrics.coordinateGutter
        let boardOrigin = CGPoint(
            x: BoardLayoutMetrics.boardFrameInset
                + (isBoardFlipped ? gutter : 0),
            y: handRackHeight
                + BoardLayoutMetrics.boardFrameInset
                + (isBoardFlipped ? 0 : gutter)
        )
        let fileIndex = isBoardFlipped ? square.file - 1 : 9 - square.file
        let rankIndex = isBoardFlipped ? 9 - square.rank : square.rank - 1
        return CGPoint(
            x: boardOrigin.x
                + (CGFloat(fileIndex) + 0.5) * boardCellSize.width,
            y: boardOrigin.y
                + (CGFloat(rankIndex) + 0.5) * boardCellSize.height
        )
    }
}

struct AnalysisMoveArrowOverlay: View {
    @ObservedObject var engine: LocalAnalysisEngine
    let sideToMove: SwiftShogi.Color
    let currentPositionSFEN: String
    let layout: AnalysisMoveArrowLayout
    let handCenter: (PieceType, SwiftShogi.Color) -> CGPoint?

    var body: some View {
        if let arrow = AnalysisMoveArrowModel.bestMove(
            state: engine.state,
            lines: engine.lines,
            sideToMove: sideToMove,
            completedSearchSFEN: engine.completedSearch?.sfen,
            currentPositionSFEN: currentPositionSFEN
        ),
           let start = startPoint(for: arrow)
        {
            AnalysisMoveArrowView(
                start: start,
                end: layout.squareCenter(arrow.destination),
                squareSize: BoardLayoutMetrics.cellSize(
                    forBoardWidth: layout.boardWidth
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("engineMoveArrow")
            .accessibilityLabel("解析中の最善手")
        }
    }

    private func startPoint(
        for arrow: AnalysisMoveArrowModel
    ) -> CGPoint? {
        switch arrow.source {
        case let .square(square):
            return layout.squareCenter(square)
        case let .hand(pieceType, color):
            return handCenter(pieceType, color)
        }
    }
}

private struct AnalysisMoveArrowView: View {
    let start: CGPoint
    let end: CGPoint
    let squareSize: CGSize

    private var unitLength: CGFloat {
        min(squareSize.width, squareSize.height)
    }

    private var shaftWidth: CGFloat {
        max(5, unitLength * 0.16)
    }

    private var headWidth: CGFloat {
        max(14, unitLength * 0.54)
    }

    private var headLength: CGFloat {
        max(16, unitLength * 0.54)
    }

    var body: some View {
        AnalysisMoveArrowShape(
            start: adjustedStart,
            end: end,
            shaftWidth: shaftWidth,
            headWidth: headWidth,
            headLength: headLength
        )
        .fill(Color.red.opacity(0.58))
        .overlay {
            AnalysisMoveArrowShape(
                start: adjustedStart,
                end: end,
                shaftWidth: shaftWidth,
                headWidth: headWidth,
                headLength: headLength
            )
            .stroke(
                Color.red.opacity(0.9),
                style: StrokeStyle(
                    lineWidth: max(1.2, shaftWidth * 0.16),
                    lineJoin: .round
                )
            )
        }
        .shadow(color: .white.opacity(0.7), radius: 1)
        .allowsHitTesting(false)
    }

    private var adjustedStart: CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.1 else {
            return start
        }
        let offset = min(length * 0.22, unitLength * 0.28)
        return CGPoint(
            x: start.x + dx / length * offset,
            y: start.y + dy / length * offset
        )
    }
}

private struct AnalysisMoveArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let shaftWidth: CGFloat
    let headWidth: CGFloat
    let headLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.1 else {
            return path
        }

        let unitX = dx / length
        let unitY = dy / length
        let perpendicularX = -unitY
        let perpendicularY = unitX
        let shaftHalf = min(shaftWidth / 2, length / 4)
        let headHalf = min(max(headWidth / 2, shaftHalf), length / 2)
        let baseDistance = max(
            length - min(headLength, length * 0.72),
            0
        )
        let base = CGPoint(
            x: start.x + unitX * baseDistance,
            y: start.y + unitY * baseDistance
        )

        path.move(
            to: CGPoint(
                x: start.x + perpendicularX * shaftHalf,
                y: start.y + perpendicularY * shaftHalf
            )
        )
        path.addLine(
            to: CGPoint(
                x: base.x + perpendicularX * shaftHalf,
                y: base.y + perpendicularY * shaftHalf
            )
        )
        path.addLine(
            to: CGPoint(
                x: base.x + perpendicularX * headHalf,
                y: base.y + perpendicularY * headHalf
            )
        )
        path.addLine(to: end)
        path.addLine(
            to: CGPoint(
                x: base.x - perpendicularX * headHalf,
                y: base.y - perpendicularY * headHalf
            )
        )
        path.addLine(
            to: CGPoint(
                x: base.x - perpendicularX * shaftHalf,
                y: base.y - perpendicularY * shaftHalf
            )
        )
        path.addLine(
            to: CGPoint(
                x: start.x - perpendicularX * shaftHalf,
                y: start.y - perpendicularY * shaftHalf
            )
        )
        path.closeSubpath()
        return path
    }
}

struct BoardView: View {
    @EnvironmentObject private var model: AppModel
    let isBoardFlipped: Bool

    var body: some View {
        GeometryReader { proxy in
            let coordinateGutter = BoardLayoutMetrics.coordinateGutter
            let boardWidth = max(1, proxy.size.width - coordinateGutter)
            let boardHeight = max(1, proxy.size.height - coordinateGutter)
            let cellWidth = boardWidth / 9
            let cellHeight = boardHeight / 9
            let boardOrigin = CGPoint(
                x: isBoardFlipped ? coordinateGutter : 0,
                y: isBoardFlipped ? 0 : coordinateGutter
            )

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    BundledPNGImage(name: "wood_warm", contentMode: .fill)
                        .frame(width: boardWidth, height: boardHeight)
                        .clipped()
                        .offset(x: boardOrigin.x, y: boardOrigin.y)

                    BoardGrid()
                        .frame(width: boardWidth, height: boardHeight)
                        .offset(x: boardOrigin.x, y: boardOrigin.y)

                    ForEach(1 ... 9, id: \.self) { rank in
                        ForEach(1 ... 9, id: \.self) { file in
                            let square = Square(file: file, rank: rank)
                            let fileIndex = isBoardFlipped ? file - 1 : 9 - file
                            let rankIndex = isBoardFlipped ? 9 - rank : rank - 1
                            let selected = model.selection == .board(square)
                            BoardSquareView(
                                square: square,
                                piece: model.position.board.at(square),
                                selected: selected,
                                lastMove: model.lastMoveDestination == square,
                                isBoardFlipped: isBoardFlipped
                            )
                            .frame(width: cellWidth, height: cellHeight)
                            .position(
                                x: boardOrigin.x
                                    + (CGFloat(fileIndex) + 0.5) * cellWidth,
                                y: boardOrigin.y
                                    + (CGFloat(rankIndex) + 0.5) * cellHeight
                            )
                            .zIndex(selected ? 1 : 0)
                        }
                    }

                    Rectangle()
                        .stroke(KifuLensTheme.boardInk, lineWidth: 1.4)
                        .frame(width: boardWidth, height: boardHeight)
                        .offset(x: boardOrigin.x, y: boardOrigin.y)
                        .allowsHitTesting(false)

                    BoardCoordinateOverlay(
                        boardWidth: boardWidth,
                        boardHeight: boardHeight,
                        gutter: coordinateGutter,
                        isBoardFlipped: isBoardFlipped
                    )
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { tap in
                        guard model.pendingPromotion == nil,
                              let square = BoardLayoutMetrics.square(
                                  at: tap.location,
                                  in: proxy.size,
                                  isBoardFlipped: isBoardFlipped
                              )
                        else {
                            return
                        }
                        model.tap(square: square)
                    }
                )

                if let pendingPromotion = model.pendingPromotion {
                    Color.black.opacity(0.18)
                        .frame(width: boardWidth, height: boardHeight)
                        .offset(x: boardOrigin.x, y: boardOrigin.y)
                        .contentShape(Rectangle())

                    PromotionChoicePanel(
                        pendingPromotion: pendingPromotion,
                        isBoardFlipped: isBoardFlipped,
                        squareSize: CGSize(
                            width: cellWidth,
                            height: cellHeight
                        ),
                        onPromote: {
                            model.applyPendingPromotion(promote: true)
                        },
                        onDecline: {
                            model.applyPendingPromotion(promote: false)
                        },
                        onCancel: model.cancelPendingPromotion
                    )
                    .frame(width: min(boardWidth - 24, cellWidth * 7.5))
                    .position(
                        x: boardOrigin.x + boardWidth / 2,
                        y: boardOrigin.y + boardHeight / 2
                    )
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.98))
                    )
                }
            }
        }
        .aspectRatio(1 / BoardLayoutMetrics.heightRatio, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("将棋盤")
    }
}

private struct BoardGrid: View {
    var body: some View {
        Canvas { context, size in
            let cellWidth = size.width / 9
            let cellHeight = size.height / 9
            var path = Path()

            for index in 0 ... 9 {
                let x = CGFloat(index) * cellWidth
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))

                let y = CGFloat(index) * cellHeight
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(KifuLensTheme.boardInk), lineWidth: 0.75)

            for file in [3, 6] {
                for rank in [3, 6] {
                    let point = CGPoint(
                        x: CGFloat(file) * cellWidth,
                        y: CGFloat(rank) * cellHeight
                    )
                    let mark = CGRect(
                        x: point.x - 2.2,
                        y: point.y - 2.2,
                        width: 4.4,
                        height: 4.4
                    )
                    context.fill(Path(ellipseIn: mark), with: .color(KifuLensTheme.boardInk))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct BoardCoordinateOverlay: View {
    let boardWidth: CGFloat
    let boardHeight: CGFloat
    let gutter: CGFloat
    let isBoardFlipped: Bool

    private let ranks = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

    var body: some View {
        let cellWidth = boardWidth / 9
        let cellHeight = boardHeight / 9

        return ZStack(alignment: .topLeading) {
            ForEach(0 ..< 9, id: \.self) { index in
                Text("\(isBoardFlipped ? index + 1 : 9 - index)")
                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(KifuLensTheme.secondaryText)
                    .position(
                        x: (isBoardFlipped ? gutter : 0)
                            + (CGFloat(index) + 0.5) * cellWidth,
                        y: isBoardFlipped
                            ? boardHeight + gutter / 2
                            : gutter / 2
                    )
            }

            ForEach(0 ..< 9, id: \.self) { index in
                Text(ranks[isBoardFlipped ? 8 - index : index])
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundStyle(KifuLensTheme.secondaryText)
                    .position(
                        x: isBoardFlipped
                            ? gutter / 2
                            : boardWidth + gutter / 2,
                        y: (isBoardFlipped ? 0 : gutter)
                            + (CGFloat(index) + 0.5) * cellHeight
                    )
            }
        }
    }
}

private struct BoardSquareView: View {
    let square: Square
    let piece: Piece?
    let selected: Bool
    let lastMove: Bool
    let isBoardFlipped: Bool

    var body: some View {
        ZStack {
            Color.clear

            if lastMove {
                Rectangle()
                    .fill(KifuLensTheme.accent.opacity(0.28))
                    .padding(1)
            }

            if let piece {
                PieceImage(
                    piece: piece,
                    lifted: selected,
                    isBoardFlipped: isBoardFlipped
                )
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let coordinate = "\(square.file)筋\(square.rank)段"
        guard let piece else {
            return "\(coordinate)、空き"
        }
        let pieceName = piece.type == .king
            ? (piece.color == .black ? "玉" : "王")
            : piece.type.kanji
        return "\(coordinate)、\(piece.color == .black ? "先手" : "後手")の\(pieceName)"
    }
}

struct PieceImage: View {
    let piece: Piece
    var lifted = false
    var isBoardFlipped = false

    var body: some View {
        BundledPNGImage(
            name: piece.type.imageAssetName(
                color: piece.color,
                isBoardFlipped: isBoardFlipped
            ),
            contentMode: .fit
        )
            .shadow(
                color: .black.opacity(lifted ? 0.55 : 0.18),
                radius: lifted ? 5 : 0.8,
                y: lifted ? 4 : 0.7
            )
            .offset(y: lifted ? -3 : 0)
    }
}

private struct PromotionChoicePanel: View {
    let pendingPromotion: PendingPromotion
    let isBoardFlipped: Bool
    let squareSize: CGSize
    let onPromote: () -> Void
    let onDecline: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KifuLensTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 8)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(KifuLensTheme.secondaryText)
                .accessibilityLabel("成り選択をキャンセル")
                .accessibilityIdentifier("promotionCancelButton")
            }

            HStack(spacing: 8) {
                promotionButton(
                    title: "成る",
                    pieceType: promotedType(
                        of: pendingPromotion.plain.pieceType
                    ),
                    accessibilityIdentifier: "promotionPromoteButton",
                    action: onPromote
                )
                promotionButton(
                    title: "成らない",
                    pieceType: pendingPromotion.plain.pieceType,
                    accessibilityIdentifier: "promotionDeclineButton",
                    action: onDecline
                )
            }
        }
        .padding(12)
        .background(KifuLensTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(KifuLensTheme.divider, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
    }

    private var title: String {
        let destination = pendingPromotion.plain.to
        return "\(fullWidthFile(destination.file))\(rankText(destination.rank))"
            + "\(pendingPromotion.plain.pieceType.kanji)を成りますか？"
    }

    private func promotionButton(
        title: String,
        pieceType: PieceType,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                PieceImage(
                    piece: Piece(
                        color: pendingPromotion.plain.color,
                        type: pieceType
                    ),
                    isBoardFlipped: isBoardFlipped
                )
                .frame(
                    width: squareSize.width * 0.78,
                    height: squareSize.height * 0.78
                )

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(KifuLensTheme.primaryText)
            .padding(.horizontal, 9)
            .frame(
                maxWidth: .infinity,
                minHeight: squareSize.height,
                alignment: .leading
            )
            .background(KifuLensTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(KifuLensTheme.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func fullWidthFile(_ file: Int) -> String {
        ["", "１", "２", "３", "４", "５", "６", "７", "８", "９"][file]
    }

    private func rankText(_ rank: Int) -> String {
        ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"][rank]
    }
}

struct HandRackView: View {
    @EnvironmentObject private var model: AppModel
    let color: SwiftShogi.Color
    let pieceSize: CGSize
    let width: CGFloat
    let isBoardFlipped: Bool

    var body: some View {
        let height = BoardLayoutMetrics.handRackHeight(
            forBoardWidth: width
        )
        let statusWidth = min(
            max(width * 0.30, height * 2.05),
            width * 0.42
        )
        let stripWidth = max(0, width - statusWidth)

        HStack(spacing: 0) {
            if color == .black {
                handPieceStrip
                    .frame(width: stripWidth, height: height)
                playerStatus
                    .frame(width: statusWidth, height: height)
            } else {
                playerStatus
                    .frame(width: statusWidth, height: height)
                handPieceStrip
                    .frame(width: stripWidth, height: height)
            }
        }
        .frame(width: width, height: height)
        .background(
            KifuLensTheme.surface,
            ignoresSafeAreaEdges: []
        )
        .overlay(alignment: isTopRow ? .bottom : .top) {
            Rectangle()
                .fill(KifuLensTheme.divider)
                .frame(height: 1)
        }
    }

    private var isTopRow: Bool {
        isBoardFlipped ? color == .black : color == .white
    }

    private var playerStatus: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Text(color == .black ? "先手" : "後手")
                    .font(.system(size: 9, weight: .medium))

                Circle()
                    .fill(
                        color == model.position.color
                            ? KifuLensTheme.accent
                            : Color.clear
                    )
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(KifuLensTheme.secondaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                color == model.position.color
                    ? "\(color == .black ? "先手" : "後手")、手番"
                    : (color == .black ? "先手" : "後手")
            )

            Text(model.playerDisplayName(for: color))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KifuLensTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .accessibilityIdentifier(
                    color == .black
                        ? "blackPlayerNameLabel"
                        : "whitePlayerNameLabel"
                )
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            KifuLensTheme.surfaceRaised,
            ignoresSafeAreaEdges: []
        )
    }

    @ViewBuilder
    private var handPieceStrip: some View {
        let pieces = handPieceTypes.filter {
            model.position.hand(color: color).count(pieceType: $0) > 0
        }

        if pieces.isEmpty {
            Text("持駒なし")
                .font(.caption)
                .foregroundStyle(KifuLensTheme.tertiaryText)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(pieces, id: \.self) { pieceType in
                        handPieceButton(pieceType)
                    }
                }
                .padding(.horizontal, 5)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func handPieceButton(_ pieceType: PieceType) -> some View {
        let count = model.position.hand(color: color).count(pieceType: pieceType)
        let selected = model.selection == .hand(pieceType)

        return Button {
            if color == model.position.color {
                model.selectHandPiece(pieceType)
            }
        } label: {
            HStack(spacing: 1) {
                PieceImage(
                    piece: Piece(color: color, type: pieceType),
                    lifted: selected,
                    isBoardFlipped: isBoardFlipped
                )
                    .frame(width: pieceSize.width, height: pieceSize.height)

                if count > 1 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(KifuLensTheme.primaryText)
                }
            }
            .padding(.horizontal, 3)
            .frame(height: pieceSize.height)
        }
        .buttonStyle(.plain)
        .disabled(color != model.position.color)
        .accessibilityLabel("\(pieceType.kanji)\(count)枚")
        .anchorPreference(
            key: AnalysisHandPieceBoundsPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [
                AnalysisHandPieceAnchorKey(
                    pieceType: pieceType,
                    color: color
                ): anchor,
            ]
        }
    }
}

private struct BundledPNGImage: View {
    let name: String
    let contentMode: ContentMode

    var body: some View {
        Image(uiImage: KifuLensImageStore.image(named: name))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: contentMode)
    }
}

private enum KifuLensImageStore {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(named name: String) -> UIImage {
        if let image = cache.object(forKey: name as NSString) {
            return image
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            preconditionFailure("画像 \(name).png がアプリ内に見つかりません。")
        }
        guard let image = UIImage(contentsOfFile: url.path) else {
            preconditionFailure("画像 \(name).png をデコードできません。")
        }

        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

extension PieceType {
    func imageAssetName(
        color: SwiftShogi.Color,
        isBoardFlipped: Bool = false
    ) -> String {
        let displayColor = isBoardFlipped ? color.reversed() : color
        let prefix = displayColor == .black ? "black" : "white"
        if self == .king {
            return displayColor == .black ? "black_king2" : "white_king"
        }
        return "\(prefix)_\(imageAssetStem)"
    }

    private var imageAssetStem: String {
        switch self {
        case .pawn: return "pawn"
        case .lance: return "lance"
        case .knight: return "knight"
        case .silver: return "silver"
        case .gold: return "gold"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .king: return "king"
        case .promPawn: return "prom_pawn"
        case .promLance: return "prom_lance"
        case .promKnight: return "prom_knight"
        case .promSilver: return "prom_silver"
        case .horse: return "horse"
        case .dragon: return "dragon"
        }
    }

    var kanji: String {
        switch self {
        case .pawn: return "歩"
        case .lance: return "香"
        case .knight: return "桂"
        case .silver: return "銀"
        case .gold: return "金"
        case .bishop: return "角"
        case .rook: return "飛"
        case .king: return "玉"
        case .promPawn: return "と"
        case .promLance: return "杏"
        case .promKnight: return "圭"
        case .promSilver: return "全"
        case .horse: return "馬"
        case .dragon: return "龍"
        }
    }
}
