import SwiftUI

struct EngineBenchmarkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("実行条件") {
                    valueRow("エンジン", model.analysisEngine.displayName)
                    valueRow(
                        "Threads",
                        "\(model.analysisSettings.threadCount)"
                    )
                    valueRow(
                        "Hash",
                        "\(model.analysisSettings.hashSizeMB) MB"
                    )
                    valueRow(
                        "各局面",
                        "\(EngineBenchmarkConfiguration.moveTimeMilliseconds / 1_000)秒"
                    )
                    valueRow(
                        "局面",
                        "\(EngineBenchmarkConfiguration.positions.count)"
                    )
                }

                Section {
                    Button {
                        Task {
                            await model.runEngineBenchmark()
                        }
                    } label: {
                        HStack {
                            if model.isRunningEngineBenchmark {
                                ProgressView()
                            } else {
                                Image(
                                    systemName:
                                        "gauge.with.dots.needle.50percent"
                                )
                            }
                            Text(
                                model.isRunningEngineBenchmark
                                    ? "実行中"
                                    : "ベンチマークを実行"
                            )
                            Spacer()
                        }
                    }
                    .disabled(
                        model.isRunningEngineBenchmark
                            || model.isAnalysisTrackingPosition
                            || model.analysisEngine.state.isBusy
                    )
                    .accessibilityIdentifier("engineBenchmarkRunButton")
                } footer: {
                    Text(
                        "通常解析と同じエンジン・評価資産で、"
                            + "benchコマンドの既定4局面を各5秒探索します。"
                    )
                }

                Section("保存済み結果") {
                    if model.engineBenchmarkRecords.isEmpty {
                        Text("まだ結果はありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.engineBenchmarkRecords) { record in
                            NavigationLink {
                                EngineBenchmarkDetailView(record: record)
                            } label: {
                                EngineBenchmarkRow(record: record)
                            }
                            .accessibilityIdentifier(
                                "engineBenchmarkResultRow"
                            )
                        }
                    }
                }
            }
            .navigationTitle("ベンチマーク")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("engineBenchmarkSheet")
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
    }
}

private struct EngineBenchmarkRow: View {
    let record: EngineBenchmarkRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(record.nodesPerSecond.formatted())
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                Text("NPS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.buildVariant)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(
                "\(record.engineName)・\(record.deviceIdentifier)・"
                    + record.startedAt.formatted(
                        date: .numeric,
                        time: .shortened
                    )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

private struct EngineBenchmarkDetailView: View {
    let record: EngineBenchmarkRecord

    var body: some View {
        List {
            Section("総計") {
                valueRow("NPS", record.nodesPerSecond.formatted())
                valueRow("Nodes", record.totalNodes.formatted())
                valueRow(
                    "Time",
                    "\(record.totalTimeMilliseconds.formatted()) ms"
                )
                if let depthLimit = record.depthLimit {
                    valueRow("Depth limit", "\(depthLimit)")
                }
                valueRow("Variant", record.buildVariant)
                valueRow("Command", record.command)
            }

            Section("環境") {
                valueRow(
                    "日時",
                    record.startedAt.formatted(
                        date: .abbreviated,
                        time: .standard
                    )
                )
                valueRow("端末", record.deviceIdentifier)
                valueRow("CPU family", record.cpuFamily)
                valueRow("OS", record.operatingSystem)
                valueRow(
                    "App",
                    "\(record.appVersion) build \(record.appBuild)"
                )
                valueRow(
                    "Thermal",
                    "\(record.startingThermalState) → "
                        + record.endingThermalState
                )
                valueRow(
                    "低電力モード",
                    record.startingLowPowerModeEnabled
                        || record.endingLowPowerModeEnabled
                        ? "有効"
                        : "無効"
                )
                valueRow("Progress", record.progressAsset)
                valueRow("Bucket", record.bucketMode)
            }

            ForEach(record.positions) { position in
                Section("局面 \(position.index)") {
                    valueRow(
                        "Depth",
                        "\(position.depth)/\(position.seldepth)"
                    )
                    valueRow("Nodes", position.nodes.formatted())
                    valueRow("NPS", position.nps.formatted())
                    valueRow(
                        "Time",
                        "\(position.timeMilliseconds.formatted()) ms"
                    )
                    valueRow("Hashfull", "\(position.hashfull)")
                    if let score = position.score {
                        valueRow("Score", score)
                    }
                    valueRow("Bestmove", position.bestmove)
                    if let ponder = position.ponder {
                        valueRow("Ponder", ponder)
                    }
                    valueRow(
                        "PV",
                        position.principalVariation.joined(separator: " ")
                    )
                    valueRow("SFEN", position.sfen)
                }
            }

            Section("USIログ") {
                Text(record.rawTranscript.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("ベンチマーク結果")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
