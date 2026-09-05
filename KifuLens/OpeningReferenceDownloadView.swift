import SwiftUI

@MainActor
final class OpeningReferenceDownloadModel: ObservableObject {
    @Published private(set) var catalog: OpeningReferenceCatalog?
    @Published private(set) var requiredBytes: Int64 = 0
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var isBusy = false
    @Published private(set) var isDownloading = false
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    private let downloader = OpeningReferenceDownloader()
    private var task: Task<Void, Never>?

    func check() {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        message = "更新情報を確認中"
        task = Task {
            defer { isBusy = false }
            do {
                guard let text = Bundle.kifuLensApplication.object(
                    forInfoDictionaryKey: "KifuLensPrecedentCatalogURL"
                ) as? String, let url = URL(string: text) else {
                    throw OpeningReferenceDownloadError.invalidCatalog
                }
                let result = try await downloader.fetchCatalog(from: url)
                try Task.checkCancellation()
                let entries = try downloader.requiredEntries(for: result)
                catalog = result
                requiredBytes = entries.reduce(0) { $0 + $1.file.compressedByteCount }
                message = requiredBytes == 0 ? "この版はダウンロード済みです" : nil
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
                message = nil
            }
        }
    }

    func install(onInstalled: @escaping (OpeningReferenceSession) -> Void) {
        guard !isBusy, let catalog else { return }
        isBusy = true
        isDownloading = true
        receivedBytes = 0
        message = "ダウンロード中"
        error = nil
        task = Task {
            defer { isBusy = false; isDownloading = false }
            do {
                let reference = try await downloader.install(catalog) { [weak self] received, _, status in
                    Task { @MainActor [weak self] in
                        guard let self, self.isDownloading else { return }
                        self.receivedBytes = received
                        self.message = status
                    }
                }
                onInstalled(reference)
                requiredBytes = 0
                message = "前例DBを更新しました"
            } catch {
                if Task.isCancelled {
                    message = "キャンセルしました。使用中の前例DBは変更していません。"
                } else {
                    self.error = error.localizedDescription
                    message = nil
                }
            }
        }
    }

    func cancel() { task?.cancel() }
}

struct OpeningReferenceDownloadView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var download = OpeningReferenceDownloadModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("配布中の前例DB") {
                    if let catalog = download.catalog {
                        Text(catalog.displayName).font(.headline)
                        LabeledContent("収録期間", value: "\(catalog.startDate)〜\(catalog.endDate)")
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        LabeledContent("対局数", value: "\(catalog.gameCount.formatted())局")
                        LabeledContent("取得サイズ", value: ByteCountFormatter.string(
                            fromByteCount: download.requiredBytes, countStyle: .file
                        ))
                    } else if download.isBusy {
                        ProgressView("更新情報を確認中")
                    }

                    if let message = download.message {
                        Text(message)
                            .font(.subheadline)
                            .accessibilityIdentifier("precedentDownloadStatus")
                    }
                    if let error = download.error {
                        Text(error).font(.subheadline).foregroundStyle(.red)
                            .accessibilityIdentifier("precedentDownloadError")
                    }
                    if download.isDownloading {
                        ProgressView(value: Double(download.receivedBytes),
                                     total: Double(max(1, download.requiredBytes)))
                        Button("キャンセル", role: .cancel, action: download.cancel)
                    } else {
                        Button(download.requiredBytes == 0 ? "この前例DBを使う" : "ダウンロードして更新") {
                            download.install(onInstalled: appModel.useDownloadedOpeningReference)
                        }
                        .disabled(download.catalog == nil || download.isBusy)
                        .accessibilityIdentifier("precedentDownloadApplyButton")
                        Button("更新情報を再確認", action: download.check)
                            .disabled(download.isBusy)
                    }
                }
                Section {
                    Text("Google Driveから前例DBだけを取得します。取得済みのファイルは再利用し、すべての検証が終わってから切り替えます。")
                    Text("ダウンロード後は通信なしで利用でき、アプリを開き直しても保持されます。通信量が多いためWi-Fiの利用をおすすめします。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("前例DBのダウンロード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { download.cancel(); dismiss() }
                }
            }
            .task { download.check() }
            .onDisappear { download.cancel() }
            .interactiveDismissDisabled(download.isDownloading)
        }
    }
}
