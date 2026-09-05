import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    private let fileDirectories = KifuLensFileDirectories()
    private let recordSaveService = RecordSaveService()
    @State private var importTarget = ImportTarget.record
    @State private var importerDirectory: URL?
    @State private var showsImporter = false
    @State private var showsRecordImportOptions = false
    @State private var showsPasteRecordSheet = false
    @State private var showsWebCSAImportSheet = false
    @State private var showsRecordSaveAlert = false
    @State private var recordSaveFileName = ""
    @State private var savedRecordMessage: String?

    var body: some View {
        ZStack {
            AppBackground()
            WorkspaceView(
                openRecord: { showsRecordImportOptions = true },
                saveRecord: prepareRecordSave,
                openBook: { showImporter(for: .book) },
                openReference: { showImporter(for: .reference) }
            )
        }
        .tint(KifuLensTheme.accent)
        .task {
            model.openInitialOpeningBookIfNeeded()
            if shouldOpenInitialOpeningReference {
                model.openInitialOpeningReferenceIfNeeded()
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: importTarget == .reference
        ) { result in
            switch importTarget {
            case .record:
                handleFileResult(result, action: model.importRecord)
            case .book:
                handleFileResult(result) {
                    model.openBook(from: $0)
                }
            case .reference:
                handleReferenceFileResult(result)
            }
        }
        .fileDialogDefaultDirectory(importerDirectory)
        .confirmationDialog(
            "棋譜を読み込む",
            isPresented: $showsRecordImportOptions,
            titleVisibility: .visible
        ) {
            Button("ファイルから開く") {
                showImporter(for: .record)
            }
            Button("テキストを貼り付け") {
                showsPasteRecordSheet = true
            }
            Button("Web CSAを指定") {
                showsWebCSAImportSheet = true
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showsPasteRecordSheet) {
            PastedRecordImportSheet()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsWebCSAImportSheet) {
            WebCSAImportSheet()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
        }
        .alert("棋譜を保存", isPresented: $showsRecordSaveAlert) {
            TextField("ファイル名", text: $recordSaveFileName)
            Button("キャンセル", role: .cancel) {}
            Button("保存") {
                saveRecord()
            }
            .disabled(
                recordSaveFileName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )
        } message: {
            Text(recordSaveMessage)
        }
        .alert(
            "棋譜を保存しました",
            isPresented: Binding(
                get: { savedRecordMessage != nil },
                set: { visible in
                    if !visible {
                        savedRecordMessage = nil
                    }
                }
            )
        ) {
            Button("閉じる") {
                savedRecordMessage = nil
            }
        } message: {
            Text(savedRecordMessage ?? "")
        }
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("閉じる"))
            )
        }
    }

    private func showImporter(for target: ImportTarget) {
        do {
            try fileDirectories.prepare()
            importTarget = target
            switch target {
            case .record:
                importerDirectory = fileDirectories.recordDirectory
            case .book:
                importerDirectory = fileDirectories.bookDirectory
            case .reference:
                importerDirectory = fileDirectories.referenceDirectory
            }
            showsImporter = true
        } catch {
            model.presentedError = PresentedError(
                title: "フォルダを準備できません",
                message: error.localizedDescription
            )
        }
    }

    private func handleFileResult(
        _ result: Result<[URL], Error>,
        action: (URL) -> Void
    ) {
        switch result {
        case let .success(urls):
            if let url = urls.first {
                action(url)
            }
        case let .failure(error):
            model.presentedError = PresentedError(
                title: "ファイルを選べません",
                message: error.localizedDescription
            )
        }
    }

    private func handleReferenceFileResult(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case let .success(urls):
            model.openReferences(from: urls)
        case let .failure(error):
            model.presentedError = PresentedError(
                title: "前例ファイルを選べません",
                message: error.localizedDescription
            )
        }
    }

    private func prepareRecordSave() {
        recordSaveFileName = model.preferredRecordSaveFileName
        showsRecordSaveAlert = true
    }

    private var shouldOpenInitialOpeningReference: Bool {
#if DEBUG
        !ProcessInfo.processInfo.arguments.contains(
            "-skip-opening-reference-startup"
        )
#else
        true
#endif
    }

    private func saveRecord() {
        do {
            let kifText = try model.exportedKIF()
            let proposedURL = try recordSaveService.destinationURL(
                named: recordSaveFileName
            )

            let url: URL
            let message: String
            switch model.saveDisposition(
                for: proposedURL.lastPathComponent,
                kifText: kifText
            ) {
            case .create:
                url = try recordSaveService.save(
                    kifText: kifText,
                    named: recordSaveFileName
                )
                message = "KifuLens/kif/\(url.lastPathComponent)"
            case let .overwrite(sourceURL):
                url = try recordSaveService.overwrite(
                    kifText: kifText,
                    at: sourceURL
                )
                message = "\(url.lastPathComponent) を更新しました。"
            case .unchanged:
                throw RecordSaveError.noChanges(proposedURL.lastPathComponent)
            }

            model.markRecordSaved(at: url, kifText: kifText)
            savedRecordMessage = message
        } catch {
            model.presentedError = PresentedError(
                title: "棋譜を保存できません",
                message: error.localizedDescription
            )
        }
    }

    private var recordSaveMessage: String {
        if model.recordFileName != nil {
            return "新しい名前はKifuLens/kifへ保存します。"
                + "開いたKIFと同じ名前なら、変更がある場合だけ元ファイルを上書きします。"
                + "一時検討も変化手順として含みます。"
        }
        return "KIF形式でKifuLens/kifへ保存します。"
            + "一時検討も変化手順として含め、既存の同名ファイルは上書きしません。"
    }
}

private enum ImportTarget {
    case record
    case book
    case reference
}

private struct PastedRecordImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 10) {
            Text("棋譜テキストを貼り付け")
                .font(.headline)
                .padding(.top)

            Text("KIF / KI2 / CSA / USI / SFEN 形式の内容を確認・編集して読み込みます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 150)
                .padding(6)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                }
                .padding(.horizontal)
                .disabled(isImporting)
                .accessibilityIdentifier("pastedRecordTextEditor")

            Button("クリップボードから貼り付け") {
                pasteFromClipboard()
            }
            .disabled(isImporting)
            .accessibilityIdentifier("pasteRecordFromClipboardButton")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("pastedRecordErrorMessage")
            }

            HStack {
                Button("キャンセル") {
                    dismiss()
                }
                .disabled(isImporting)

                Spacer()

                Button {
                    importRecord()
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Text("読み込む")
                    }
                }
                .disabled(
                    isImporting
                        || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("pastedRecordImportButton")
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func pasteFromClipboard() {
        let pasted = UIPasteboard.general.string ?? ""
        text = pasted
        errorMessage = pasted.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? "クリップボードに棋譜テキストがありません。" : nil
    }

    private func importRecord() {
        let source = text
        isImporting = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try RecordImportService.load(text: source)
                }.value
                model.replaceRecord(with: payload)
                dismiss()
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct WebCSAImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var urlText = ""
    @State private var errorMessage: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 10) {
            Text("Web CSAを読み込む")
                .font(.headline)
                .padding(.top)

            Text("公開されているCSA棋譜のURLを指定します。取得は今回の一度だけで、自動更新はしません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextEditor(text: $urlText)
                .font(.body.monospaced())
                .frame(minHeight: 80)
                .padding(6)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                }
                .padding(.horizontal)
                .disabled(isImporting)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("webCSAURLTextEditor")

            Button("クリップボードから貼り付け") {
                urlText = UIPasteboard.general.string ?? ""
                errorMessage = nil
            }
            .disabled(isImporting)
            .accessibilityIdentifier("pasteWebCSAURLButton")

            if isImporting {
                ProgressView("取得中…")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("webCSAImportErrorMessage")
            }

            HStack {
                Button("キャンセル") {
                    dismiss()
                }
                .disabled(isImporting)

                Spacer()

                Button("取り込む") {
                    importCSA()
                }
                .disabled(
                    isImporting
                        || WebCSAImportService.parseURL(from: urlText) == nil
                )
                .accessibilityIdentifier("webCSAImportButton")
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func importCSA() {
        guard let url = WebCSAImportService.parseURL(from: urlText) else {
            return
        }

        isImporting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let result = try await WebCSAImportService().importCSA(from: url)
                model.replaceRecord(with: result.payload)
                dismiss()
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
