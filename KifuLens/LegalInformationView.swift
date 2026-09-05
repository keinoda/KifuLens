import Foundation
import SwiftUI

enum LegalDocument: CaseIterable, Hashable {
    case termsOfUse
    case privacyPolicy
    case openSourceLicenses
    case gplVersion3

    var title: String {
        switch self {
        case .termsOfUse:
            return "利用規約"
        case .privacyPolicy:
            return "プライバシーポリシー"
        case .openSourceLicenses:
            return "オープンソースライセンス"
        case .gplVersion3:
            return "GNU GPL version 3"
        }
    }

    var resourceName: String {
        switch self {
        case .termsOfUse:
            return "TermsOfUse"
        case .privacyPolicy:
            return "PrivacyPolicy"
        case .openSourceLicenses:
            return "OpenSourceLicenses"
        case .gplVersion3:
            return "LICENSE"
        }
    }

    var resourceExtension: String? {
        self == .gplVersion3 ? nil : "md"
    }

    var accessibilityIdentifier: String {
        switch self {
        case .termsOfUse:
            return "termsOfUseLink"
        case .privacyPolicy:
            return "privacyPolicyLink"
        case .openSourceLicenses:
            return "openSourceLicensesLink"
        case .gplVersion3:
            return "gplVersion3Link"
        }
    }
}

enum LegalDocumentError: LocalizedError {
    case resourceNotFound(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case let .resourceNotFound(name):
            return "法務文書「\(name)」がアプリ内に見つかりません。"
        case let .unreadable(name):
            return "法務文書「\(name)」を読み込めません。"
        }
    }
}

struct LegalDocumentStore {
    let bundle: Bundle

    init(bundle: Bundle = .kifuLensApplication) {
        self.bundle = bundle
    }

    func text(for document: LegalDocument) throws -> String {
        guard let url = bundle.url(
            forResource: document.resourceName,
            withExtension: document.resourceExtension
        ) else {
            throw LegalDocumentError.resourceNotFound(document.title)
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw LegalDocumentError.unreadable(document.title)
        }
    }
}

private final class KifuLensBundleToken {}

extension Bundle {
    static var kifuLensApplication: Bundle {
        Bundle(for: KifuLensBundleToken.self)
    }
}

struct LegalInformationView: View {
    @Environment(\.dismiss) private var dismiss

    private var versionDescription: String {
        let info = Bundle.kifuLensApplication.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "不明"
        let build = info?["CFBundleVersion"] as? String ?? "不明"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("バージョン", value: versionDescription)
                        .accessibilityIdentifier("legalVersionLabel")
                }

                Section("法務情報") {
                    documentLink(
                        .termsOfUse,
                        icon: "doc.text"
                    )
                    documentLink(
                        .privacyPolicy,
                        icon: "hand.raised"
                    )
                    documentLink(
                        .openSourceLicenses,
                        icon: "shippingbox"
                    )
                    documentLink(
                        .gplVersion3,
                        icon: "text.document"
                    )
                }
            }
            .navigationTitle("情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("legalInformationSheet")
    }

    private func documentLink(
        _ document: LegalDocument,
        icon: String
    ) -> some View {
        NavigationLink {
            LegalDocumentView(document: document)
        } label: {
            Label(document.title, systemImage: icon)
        }
        .accessibilityIdentifier(document.accessibilityIdentifier)
    }
}

private struct LegalDocumentView: View {
    let document: LegalDocument
    @State private var text: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let text {
                if document == .gplVersion3 {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 12, design: .monospaced))
                            .lineSpacing(1)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                            .accessibilityIdentifier("legalDocumentText")
                    }
                } else {
                    LegalMarkdownView(source: text)
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "文書を表示できません",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadDocument()
        }
    }

    private func loadDocument() {
        guard text == nil, errorMessage == nil else {
            return
        }
        do {
            text = try LegalDocumentStore().text(for: document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LegalMarkdownBlock: Identifiable, Equatable {
    enum Style: Equatable {
        case title
        case heading
        case paragraph
        case bullet
        case quote
    }

    let id: Int
    let style: Style
    let text: String
}

enum LegalMarkdownParser {
    static func blocks(from source: String) -> [LegalMarkdownBlock] {
        var blocks: [LegalMarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []

        func append(_ style: LegalMarkdownBlock.Style, _ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            blocks.append(
                LegalMarkdownBlock(
                    id: blocks.count,
                    style: style,
                    text: trimmed
                )
            )
        }

        func flushParagraph() {
            append(.paragraph, paragraph.joined(separator: " "))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            append(.quote, quote.joined(separator: " "))
            quote.removeAll(keepingCapacity: true)
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                flushQuote()
            } else if line.hasPrefix("## ") {
                flushParagraph()
                flushQuote()
                append(.heading, String(line.dropFirst(3)))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                flushQuote()
                append(.title, String(line.dropFirst(2)))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                flushQuote()
                append(.bullet, String(line.dropFirst(2)))
            } else if line.hasPrefix(">") {
                flushParagraph()
                let content = String(line.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    flushQuote()
                } else {
                    quote.append(content)
                }
            } else {
                flushQuote()
                paragraph.append(line)
            }
        }

        flushParagraph()
        flushQuote()
        return blocks
    }
}

private struct LegalMarkdownView: View {
    let source: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(LegalMarkdownParser.blocks(from: source)) { block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
            .accessibilityIdentifier("legalDocumentText")
        }
    }

    @ViewBuilder
    private func blockView(_ block: LegalMarkdownBlock) -> some View {
        switch block.style {
        case .title:
            Text(inlineMarkdown(block.text))
                .font(.title3.weight(.bold))
        case .heading:
            Text(inlineMarkdown(block.text))
                .font(.headline)
                .padding(.top, 4)
        case .paragraph:
            Text(inlineMarkdown(block.text))
                .font(.system(size: 14))
                .lineSpacing(3)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                Text(inlineMarkdown(block.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 14))
        case .quote:
            Text(inlineMarkdown(block.text))
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(source)
    }
}
