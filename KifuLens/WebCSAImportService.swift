import Foundation
import SwiftShogi

enum WebCSAImportError: LocalizedError, Equatable {
    case unsupportedURL
    case httpStatus(Int)
    case emptyResponse
    case unsupportedEncoding
    case csaNotFound
    case networkFailure(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "対応していないURLです。httpsで始まるCSA棋譜のURLを指定してください。"
        case let .httpStatus(code):
            return "URL先からの取得に失敗しました（HTTP \(code)）。"
        case .emptyResponse:
            return "取得した内容が空でした。"
        case .unsupportedEncoding:
            return "取得した内容を文字列としてデコードできませんでした。"
        case .csaNotFound:
            return "URL先からCSA棋譜を確認できませんでした。"
        case let .networkFailure(description):
            return "通信エラーが発生しました: \(description)"
        }
    }
}

protocol WebCSADataFetching {
    func fetchData(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: WebCSADataFetching {
    func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

struct WebCSAImportResult {
    let payload: RecordImportPayload
    let sourceName: String
}

struct WebCSAImportService {
    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
        + "Version/17.6 Mobile/15E148 Safari/604.1"

    let fetcher: any WebCSADataFetching
    let userAgent: String

    init(
        fetcher: any WebCSADataFetching = WebCSAImportService.defaultSession(),
        userAgent: String = WebCSAImportService.defaultUserAgent
    ) {
        self.fetcher = fetcher
        self.userAgent = userAgent
    }

    func importCSA(from url: URL) async throws -> WebCSAImportResult {
        guard Self.isSupported(url) else {
            throw WebCSAImportError.unsupportedURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("ja,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetcher.fetchData(for: request)
        } catch {
            throw WebCSAImportError.networkFailure(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode)
        {
            throw WebCSAImportError.httpStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            throw WebCSAImportError.emptyResponse
        }

        let httpResponse = response as? HTTPURLResponse
        guard let decoded = WebCSATextDecoder.decode(
            data: data,
            hintedBy: httpResponse
        ) else {
            throw WebCSAImportError.unsupportedEncoding
        }

        let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw WebCSAImportError.emptyResponse
        }
        guard !Self.looksLikeHTML(text),
              FormatDetector.detectRecordFormat(text) == .CSA,
              Self.containsCSAMarkers(text)
        else {
            throw WebCSAImportError.csaNotFound
        }

        return WebCSAImportResult(
            payload: try RecordImportService.load(
                text: text,
                title: Self.suggestedTitle(for: url)
            ),
            sourceName: url.host ?? url.absoluteString
        )
    }

    static func parseURL(from text: String) -> URL? {
        let candidates = text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return candidates.compactMap(URL.init(string:)).first(where: isSupported)
    }

    static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !host.isEmpty
        else {
            return false
        }
        return true
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let head = text.prefix(2_048).lowercased()
        return head.contains("<!doctype html")
            || head.contains("<html")
            || (head.contains("<head") && head.contains("<body"))
    }

    private static func containsCSAMarkers(_ text: String) -> Bool {
        text.range(
            of: "(?m)^[+\\-][0-9]{4}[A-Z]{2}",
            options: .regularExpression
        ) != nil
            || text.range(of: "(?m)^P[1-9I]", options: .regularExpression) != nil
            || text.range(of: "(?m)^N[+\\-]", options: .regularExpression) != nil
    }

    private static func suggestedTitle(for url: URL) -> String {
        let lastPath = url.lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutExtension = (lastPath as NSString).deletingPathExtension
        if !withoutExtension.isEmpty {
            return withoutExtension
        }
        return url.host ?? "Web CSA"
    }
}

enum WebCSATextDecoder {
    private static let candidates: [String.Encoding] = [
        .utf8,
        .shiftJIS,
        .japaneseEUC,
        .isoLatin1,
    ]

    static func decode(data: Data, hintedBy response: HTTPURLResponse?) -> String? {
        if let response,
           let encoding = encoding(
               from: response.value(forHTTPHeaderField: "Content-Type")
           ),
           let text = String(data: data, encoding: encoding)
        {
            return text
        }

        if let preview = String(data: data.prefix(2_048), encoding: .isoLatin1),
           let metaEncoding = encoding(fromHTMLMeta: preview),
           let text = String(data: data, encoding: metaEncoding)
        {
            return text
        }

        for encoding in candidates {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }

    private static func encoding(from contentType: String?) -> String.Encoding? {
        guard let contentType,
              let range = contentType.range(
                  of: "charset=",
                  options: .caseInsensitive
              )
        else {
            return nil
        }
        let value = contentType[range.upperBound...]
            .split(separator: ";", maxSplits: 1).first ?? ""
        let charset = value
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            .lowercased()
        return encoding(forCharsetName: charset)
    }

    private static func encoding(fromHTMLMeta html: String) -> String.Encoding? {
        guard let regex = try? NSRegularExpression(
            pattern: "<meta[^>]+charset\\s*=\\s*[\"']?([A-Za-z0-9_\\-]+)",
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(location: 0, length: html.utf16.count)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }
        return encoding(forCharsetName: String(html[captureRange]))
    }

    private static func encoding(forCharsetName charset: String) -> String.Encoding? {
        switch charset.lowercased() {
        case "utf-8", "utf8":
            return .utf8
        case "shift_jis", "shift-jis", "sjis", "x-sjis",
             "windows-31j", "cp932", "ms932":
            return .shiftJIS
        case "euc-jp", "eucjp", "x-euc-jp":
            return .japaneseEUC
        case "iso-8859-1", "latin1":
            return .isoLatin1
        case "us-ascii", "ascii":
            return .ascii
        default:
            return nil
        }
    }
}
