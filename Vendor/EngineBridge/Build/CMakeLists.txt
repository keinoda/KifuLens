cmake_minimum_required(VERSION 3.25)
project(KifuLensNative LANGUAGES C CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include("${ENGINE_CONFIGURATION}")

set(COMMON_SOURCES
    types.cpp
    bitboard.cpp
    misc.cpp
    movegen.cpp
    position.cpp
    usi.cpp
    usioption.cpp
    thread.cpp
    tt.cpp
    movepick.cpp
    timeman.cpp
    memory.cpp
    engine.cpp
    search.cpp
    score.cpp
    benchmark.cpp
    tune.cpp
    book/book.cpp
    book/apery_book.cpp
    book/policybook.cpp
    book/makebook.cpp
    book/makebook2025.cpp
    extra/bitop.cpp
    extra/long_effect.cpp
    extra/sfen_packer.cpp
    mate/mate.cpp
    mate/mate1ply_without_effect.cpp
    mate/mate1ply_with_effect.cpp
    mate/mate_solver.cpp
    eval/evaluate_bona_piece.cpp
    eval/evaluate.cpp
    eval/evaluate_io.cpp
    eval/evaluate_mir_inv_tools.cpp
    eval/material/evaluate_material.cpp
    testcmd/unit_test.cpp
    testcmd/mate_test_cmd.cpp
    testcmd/normal_test_cmd.cpp
    eval/nnue/evaluate_nnue.cpp
    eval/nnue/nnue_test_command.cpp
    engine/yaneuraou-engine/yaneuraou-search.cpp
)

add_library(KifuLensNative STATIC "${CMAKE_CURRENT_BINARY_DIR}/registry.cpp")
set_property(TARGET KifuLensNative PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
target_include_directories(KifuLensNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/KifuLensEngine/include")

foreach(id IN LISTS ENGINE_IDS)
    set(root "${ENGINE_${id}_SOURCE}")
    set(sources "${CMAKE_CURRENT_LIST_DIR}/ios_main.cpp")
    foreach(relative IN LISTS COMMON_SOURCES)
        if(NOT EXISTS "${root}/${relative}")
            message(FATAL_ERROR "${id}: 対応するエンジンソースがありません: ${relative}")
        endif()
        list(APPEND sources "${root}/${relative}")
    endforeach()
    file(GLOB features CONFIGURE_DEPENDS "${root}/eval/nnue/features/*.cpp")
    list(APPEND sources ${features})
    if(EXISTS "${root}/tanuki_progress.cpp")
        list(APPEND sources "${root}/tanuki_progress.cpp")
        set_source_files_properties("${root}/tanuki_progress.cpp" PROPERTIES COMPILE_OPTIONS "-fno-lto")
    endif()
    if(ENGINE_${id}_POLICY)
        list(APPEND sources "${root}/eval/deep/nn_types.cpp" "${CMAKE_CURRENT_LIST_DIR}/policy_value_coreml.mm")
    endif()
    add_library(engine_${id} OBJECT ${sources})
    set_property(TARGET engine_${id} PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
    target_include_directories(engine_${id} PRIVATE "${root}" "${CMAKE_CURRENT_LIST_DIR}"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/KifuLensEngine/include")
    string(TOUPPER "${id}" banner)
    target_compile_definitions(engine_${id} PRIVATE
        _LINUX UNICODE NO_EXCEPTIONS IS_64BIT NDEBUG FOR_TOURNAMENT YANEURAOU_ENGINE_NNUE
        NNUE_EMBEDDING_OFF HASH_KEY_BITS=128 TT_CLUSTER_SIZE=4 USE_LAZY_EVALUATE
        ENGINE_NAME_FROM_MAKEFILE=${banner}
        ENGINE_RUNTIME=KifuLensRuntime_${id}
        ENGINE_ENTRY=engine_${id}_start
        YaneuraOu=KifuLens_${id}_YaneuraOu
        Tanuki=KifuLens_${id}_Tanuki
        eval_loaded=KifuLens_${id}_eval_loaded
        last_eval_dir=KifuLens_${id}_last_eval_dir
        "NNUE_ARCHITECTURE_HEADER=\"architectures/${ENGINE_${id}_ARCHITECTURE}.h\""
        ${ENGINE_${id}_DEFINES})
    if(ENGINE_${id}_ARCHITECTURE MATCHES "^SFNN_")
        target_compile_definitions(engine_${id} PRIVATE SFNNwoPSQT)
    endif()
    if(ENGINE_${id}_POLICY)
        target_compile_definitions(engine_${id} PRIVATE NAGISA_POLICY_VALUE_COREML KIFULENS_HAS_POLICY)
    endif()
    target_compile_options(engine_${id} PRIVATE -fno-exceptions -fno-rtti -Wextra -fpermissive -Ofast)
    if(ENGINE_CPU STREQUAL "neon")
        target_compile_definitions(engine_${id} PRIVATE USE_NEON=8 USE_NEON_DOTPROD)
        target_compile_options(engine_${id} PRIVATE -march=armv8.2-a+fp16+rcpc+dotprod+crypto -mtune=apple-a13)
    elseif(ENGINE_CPU STREQUAL "avx2")
        target_compile_definitions(engine_${id} PRIVATE USE_AVX2 USE_BMI2)
        target_compile_options(engine_${id} PRIVATE -mbmi -mbmi2 -mavx2 -mpopcnt)
    else()
        message(FATAL_ERROR "ENGINE_CPUはneonまたはavx2で指定してください")
    endif()
    target_sources(KifuLensNative PRIVATE $<TARGET_OBJECTS:engine_${id}>)
endforeach()

set_source_files_properties(policy_value_coreml.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")
