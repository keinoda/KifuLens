#!/usr/bin/env python3
"""設定からエンジンの静的ライブラリ・アプリ用の定義・資産を生成する。"""

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

BUILD_DIRECTORY = Path(__file__).resolve().parent
REPOSITORY = BUILD_DIRECTORY.parents[2]
IDENTIFIER = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*\Z")
ARCHITECTURE = re.compile(r"[A-Za-z0-9_-]+\Z")
RESERVED_OPTIONS = {"Threads", "USI_Hash", "MultiPV", "EvalDir"}


@dataclass
class Engine:
    identifier: str
    display_name: str
    version: str
    comment_name: str
    source: Path
    patch: Path
    architecture: str
    nnue: Path
    progress: object
    options: dict
    defines: list

    @property
    def stem(self):
        return self.identifier.replace("-", "_")


@dataclass
class Configuration:
    engines: list
    default_engine: str
    policy_engine: str


def required_text(value, field):
    if not isinstance(value, str) or not value or not value.isprintable():
        raise ValueError(f"{field}: 空でない文字列を指定してください")
    return value


def input_file(root, value, field):
    path = (root / required_text(value, field)).resolve()
    if not path.is_file():
        raise ValueError(f"{field}: ファイルが見つかりません: {path}")
    return path


def option_text(value, field):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return required_text(value, field)


def load_configuration(path, root=REPOSITORY):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict) or set(data) != {"engines", "defaultEngine", "policyEngine"}:
        raise ValueError("設定の先頭には engines、defaultEngine、policyEngine を指定してください")
    if not isinstance(data["engines"], list) or not data["engines"]:
        raise ValueError("engines: エンジンを一つ以上指定してください")
    engines = []
    identifiers = set()
    required = {"id", "displayName", "version", "source", "patch", "architecture", "nnue", "options"}
    allowed = required | {"commentName", "progress", "defines"}
    for item in data["engines"]:
        if not isinstance(item, dict) or required - set(item) or set(item) - allowed:
            raise ValueError(f"エンジン設定のキーが不正です。必須: {sorted(required)}、任意: {sorted(allowed - required)}")
        identifier = required_text(item["id"], "id")
        if not IDENTIFIER.fullmatch(identifier) or identifier in identifiers:
            raise ValueError(f"id: 重複しない英小文字・数字・ハイフンの名前を指定してください: {identifier}")
        identifiers.add(identifier)
        source = (root / required_text(item["source"], f"{identifier}.source")).resolve()
        for relative in ["source/config.h", "source/eval/nnue/architectures/nnue_arch_gen.py"]:
            if not (source / relative).is_file():
                raise ValueError(f"{identifier}.source: 対応するYaneuraOuのソースが見つかりません: {source / relative}")
        architecture = required_text(item["architecture"], f"{identifier}.architecture")
        if not ARCHITECTURE.fullmatch(architecture):
            raise ValueError(f"{identifier}.architecture: architecture名の形式が不正です")
        patch = input_file(root, item["patch"], f"{identifier}.patch")
        nnue = input_file(root, item["nnue"], f"{identifier}.nnue")
        progress = input_file(root, item["progress"], f"{identifier}.progress") if item.get("progress") is not None else None
        if nnue.stat().st_size == 0 or (progress and progress.stat().st_size == 0):
            raise ValueError(f"{identifier}: 評価資産が空です")
        if not isinstance(item["options"], dict):
            raise ValueError(f"{identifier}.options: USIオプション名と値の辞書を指定してください")
        options = {}
        for name, value in item["options"].items():
            required_text(name, f"{identifier}.options")
            if name in RESERVED_OPTIONS:
                raise ValueError(f"{identifier}.options: {name}はアプリ側で管理するため指定できません")
            value = option_text(value, f"{identifier}.options.{name}")
            if value == "@progress" and progress is None:
                raise ValueError(f"{identifier}: @progressを使う場合はprogressファイルを指定してください")
            options[name] = value
        defines = item.get("defines", [])
        if not isinstance(defines, list) or any(not isinstance(v, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*(?:=[A-Za-z_0-9.+-]+)?", v) for v in defines):
            raise ValueError(f"{identifier}.defines: コンパイラー定義の文字列配列を指定してください")
        display_name = required_text(item["displayName"], f"{identifier}.displayName")
        engines.append(Engine(identifier, display_name,
                              required_text(item["version"], f"{identifier}.version"),
                              required_text(item.get("commentName", display_name), f"{identifier}.commentName"),
                              source, patch, architecture, nnue, progress, options, defines))
    for name in ["defaultEngine", "policyEngine"]:
        if data[name] not in identifiers:
            raise ValueError(f"{name}: enginesに登録したidを指定してください")
    return Configuration(engines, data["defaultEngine"], data["policyEngine"])


def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)


def swift_configuration(configuration):
    entries = []
    for engine in configuration.engines:
        progress_size = str(engine.progress.stat().st_size) if engine.progress else "nil"
        options = ",\n                    ".join(
            f"EngineUSIOption(name: {quoted(name)}, value: {quoted(value)})"
            for name, value in engine.options.items()
        )
        entries.append(f'''        BundledEngineConfiguration(
            descriptor: AnalysisEngineDescriptor(
                id: AnalysisEngineIdentifier(rawValue: {quoted(engine.identifier)}),
                displayName: {quoted(engine.display_name)}, version: {quoted(engine.version)},
                commentName: {quoted(engine.comment_name)}
            ),
            assets: LocalAnalysisAssetSpecification(
                directoryName: {quoted(engine.identifier)},
                nnueSize: {engine.nnue.stat().st_size}, progressSize: {progress_size},
                bucketMode: {quoted(engine.options.get("LS_BUCKET_MODE", "architecture"))}
            ),
            options: [{options}]
        )''')
    default_index = [e.identifier for e in configuration.engines].index(configuration.default_engine)
    joined_entries = ",\n".join(entries)
    return "// engines.jsonから生成。変更は設定ファイルで行ってください。\n" + f'''enum CompiledEngineConfiguration {{
    static let engines: [BundledEngineConfiguration] = [
{joined_entries}
    ]
    static let defaultEngine = engines[{default_index}]
    static let policyEngine = AnalysisEngineIdentifier(rawValue: {quoted(configuration.policy_engine)})
}}
'''


def registry_source(configuration):
    declarations = "\n".join(f'extern "C" int engine_{e.stem}_start(KifuLensSession, const char*);' for e in configuration.engines)
    entries = ",\n".join(f'    {{{quoted(e.identifier)}, engine_{e.stem}_start}}' for e in configuration.engines)
    return f'''#include "ios_runtime.h"
#include <atomic>
#include <cstring>

{declarations}

namespace {{
std::atomic_bool running = false;
struct Entry {{ const char* id; int (*start)(KifuLensSession, const char*); }};
const Entry entries[] = {{
{entries}
}};
}}

void kifulens_session_finished(const KifuLensSession& session) {{
    running.store(false);
    session.did_exit(session.context);
}}

extern "C" int kifulens_native_start(
    const char* id, kifulens_usi_read_cb read, kifulens_usi_write_cb write,
    kifulens_exit_cb did_exit, void* context, const char* directory
) {{
    if (!id || !read || !write || !did_exit) return -1;
    for (const auto& entry : entries) {{
        if (std::strcmp(id, entry.id) != 0) continue;
        if (running.exchange(true)) return -2;
        const int result = entry.start({{read, write, did_exit, context}}, directory);
        if (result != 0) running.store(false);
        return result;
    }}
    return -3;
}}
'''


def run(arguments, **kwargs):
    print("+", " ".join(str(v) for v in arguments), flush=True)
    subprocess.run([str(v) for v in arguments], check=True, **kwargs)


def cmake_text(value):
    # CMakeのリスト区切りと引用符を保護する。
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"').replace(";", "\\;") + '"'


def prepare_slice(configuration, directory):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "registry.cpp").write_text(registry_source(configuration), encoding="utf-8")
    values = ["set(ENGINE_IDS " + " ".join(e.stem for e in configuration.engines) + ")"]
    for engine in configuration.engines:
        workspace = directory / "engines" / engine.stem
        source = workspace / "source"
        # 生成用コピーだけを置き換え、submoduleには書き込まない。
        if source.exists():
            shutil.rmtree(source)
        workspace.mkdir(parents=True, exist_ok=True)
        shutil.copytree(engine.source / "source", source, ignore=shutil.ignore_patterns("*.bin", "*.o", "*.a"))
        run(["patch", "-p1", "-f", "-i", engine.patch], cwd=workspace)
        run([sys.executable, source / "eval/nnue/architectures/nnue_arch_gen.py",
             engine.architecture, source / "eval/nnue/architectures"], cwd=source)
        for key, value in {
            "SOURCE": source,
            "ARCHITECTURE": engine.architecture,
            "POLICY": "ON" if engine.identifier == configuration.policy_engine else "OFF",
        }.items():
            values.append(f"set(ENGINE_{engine.stem}_{key} {cmake_text(value)})")
        values.append(f"set(ENGINE_{engine.stem}_DEFINES " + " ".join(cmake_text(v) for v in engine.defines) + ")")
    manifest = directory / "engines.cmake"
    manifest.write_text("\n".join(values) + "\n", encoding="utf-8")
    return manifest


def publish_resources(configuration, root):
    source_folders = []
    for engine in configuration.engines:
        relative = Path("KifuLens/EngineAssets") / engine.identifier
        target = root / relative / "eval"
        target.mkdir(parents=True, exist_ok=True)
        # 標準同梱資産を再ビルドする場合は、入力と出力が同じファイルになる。
        if engine.nnue.resolve() != (target / "nn.bin").resolve():
            shutil.copy2(engine.nnue, target / "nn.bin")
        if engine.progress and engine.progress.resolve() != (target / "progress.bin").resolve():
            shutil.copy2(engine.progress, target / "progress.bin")
        source_folders.append({"path": str(relative), "type": "folder", "buildPhase": "resources"})
    specification = {"targets": {"KifuLens": {"sources": source_folders}}}
    (root / "engine-resources.yml").write_text(json.dumps(specification, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    generated = root / "KifuLens/Generated"
    generated.mkdir(parents=True, exist_ok=True)
    (generated / "CompiledEngineConfiguration.swift").write_text(swift_configuration(configuration), encoding="utf-8")


def publish_outputs(configuration, slices, root, build_root):
    framework = root / "Vendor/EngineBridge/Frameworks/KifuLensNative.xcframework"
    header = root / "Vendor/EngineBridge/Sources/KifuLensEngine/include/kifulens_engine.h"
    libraries = []
    for identifier, architectures, platform_variant, sources in slices:
        target = framework / identifier
        (target / "Headers").mkdir(parents=True, exist_ok=True)
        library = target / "libKifuLensNative.a"
        if len(sources) == 1:
            shutil.copy2(sources[0], library)
        else:
            run(["lipo", "-create", *sources, "-output", library])
        shutil.copy2(header, target / "Headers/kifulens_engine.h")
        entry = {"BinaryPath": library.name, "HeadersPath": "Headers", "LibraryIdentifier": identifier,
                 "LibraryPath": library.name, "SupportedArchitectures": architectures, "SupportedPlatform": "ios"}
        if platform_variant:
            entry["SupportedPlatformVariant"] = platform_variant
        libraries.append(entry)
    (framework / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries,
        "CFBundlePackageType": "XFWK", "XCFrameworkFormatVersion": "1.0"}))
    publish_resources(configuration, root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=REPOSITORY / "engines.json")
    parser.add_argument("--check", action="store_true", help="設定と入力ファイルだけを検証する")
    parser.add_argument("--platform", choices=["all", "simulator", "device"], default="all")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobsは1以上で指定してください")
    try:
        configuration = load_configuration(args.config)
        print("構成:", ", ".join(e.identifier for e in configuration.engines), flush=True)
        if args.check:
            return
        build_root = REPOSITORY / ".build-engines"
        platforms = []
        if args.platform in ("all", "device"):
            platforms.append(("ios-arm64", "iphoneos", "arm64", "neon"))
        if args.platform in ("all", "simulator"):
            platforms += [("sim-arm64", "iphonesimulator", "arm64", "neon"),
                          ("sim-x86_64", "iphonesimulator", "x86_64", "avx2")]
        for name, sdk, architecture, cpu in platforms:
            directory = build_root / name
            manifest = prepare_slice(configuration, directory)
            run(["cmake", "-S", BUILD_DIRECTORY, "-B", directory, "-G", "Unix Makefiles",
                 "-DCMAKE_SYSTEM_NAME=iOS", f"-DCMAKE_OSX_SYSROOT={sdk}",
                 f"-DCMAKE_OSX_ARCHITECTURES={architecture}", "-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0",
                 "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY", "-DCMAKE_BUILD_TYPE=Release",
                 f"-DENGINE_CONFIGURATION={manifest}", f"-DENGINE_CPU={cpu}"])
            run(["cmake", "--build", directory, "--parallel", args.jobs])
        slices = []
        if args.platform in ("all", "device"):
            slices.append(("ios-arm64", ["arm64"], None, [build_root / "ios-arm64/libKifuLensNative.a"]))
        if args.platform in ("all", "simulator"):
            slices.append(("ios-arm64_x86_64-simulator", ["arm64", "x86_64"], "simulator",
                           [build_root / "sim-arm64/libKifuLensNative.a", build_root / "sim-x86_64/libKifuLensNative.a"]))
        publish_outputs(configuration, slices, REPOSITORY, build_root)
        print("静的ライブラリ・エンジン一覧・評価資産を生成しました。次に xcodegen generate を実行してください。")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"エンジンの準備に失敗しました: {error}\n")


if __name__ == "__main__":
    main()
