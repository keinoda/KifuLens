import Foundation

enum ProductScope {
    static let includedFeatures = [
        "棋譜末尾の直線延長と分岐時の一時検討",
        "一時検討を棋譜の変化手順へ取り込み",
        "KIF・KI2・CSA・SFEN・USIのファイル・貼り付け読み取り",
        "Web CSA棋譜の一回取得",
        "KIF棋譜の名前付き保存と開いたKIFの更新保存",
        "同梱したエンジンと解析条件を切り替えられる端末内解析",
        "ペタショックYBB定跡のLZFSE圧縮同梱と巨大な.db・.ybb定跡の閲覧",
    ]

    static let excludedFeatures = [
        "CSA対局接続",
        "Web棋譜の自動再読み込み",
        "オンライン対局",
        "クラウドエンジン",
        "汎用的な棋譜編集・定跡編集と無関係な既存ファイルへの上書き",
        "アカウントと同期",
    ]
}
