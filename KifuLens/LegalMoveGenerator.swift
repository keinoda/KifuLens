import SwiftShogi

enum LegalMoveGenerator {
    static func moves(in position: ImmutablePosition) -> [Move] {
        var result: [Move] = []
        let color = position.color

        let ownSquares = position.board.listNonEmptySquares().filter {
            position.board.at($0)?.color == color
        }
        for from in ownSquares {
            for to in Square.allSquares {
                guard let plain = position.createMove(from: .left(from), to: to) else {
                    continue
                }

                if position.mustPromote(plain) {
                    let promoted = plain.withPromote()
                    if position.isValidMove(promoted) {
                        result.append(promoted)
                    }
                    continue
                }

                if position.isValidMove(plain) {
                    result.append(plain)
                }

                if position.canPromote(plain) {
                    let promoted = plain.withPromote()
                    if position.isValidMove(promoted) {
                        result.append(promoted)
                    }
                }
            }
        }

        for pieceType in handPieceTypes where position.hand(color: color).count(pieceType: pieceType) > 0 {
            for to in Square.allSquares {
                guard let move = position.createMove(from: .right(pieceType), to: to),
                      position.isValidMove(move)
                else {
                    continue
                }
                result.append(move)
            }
        }

        return result
    }
}
