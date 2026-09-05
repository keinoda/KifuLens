#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

#include "eval/deep/nn_types.h"
#include "ios_runtime.h"
#include "movegen.h"
#include "kifulens_engine.h"
#include "position.h"
#include "types.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {

std::mutex policy_value_mutex;
MLModel* loaded_model;
std::string loaded_model_path;

// ふかうら王のSoftmax_Temperature既定値174を実温度へ換算する。
constexpr double policy_softmax_temperature = 1.74;

void write_error(
    char* error_message,
    int error_message_capacity,
    const std::string& message
) {
    if (!error_message || error_message_capacity <= 0) {
        return;
    }
    std::snprintf(
        error_message,
        static_cast<size_t>(error_message_capacity),
        "%s",
        message.c_str()
    );
}

std::string describe_error(NSString* prefix, NSError* error) {
    NSString* description = error.localizedDescription ?: @"不明なエラー";
    return std::string(
        [[NSString stringWithFormat:@"%@: %@", prefix, description] UTF8String]
    );
}

MLModel* load_model(const std::string& path, std::string& error_message) {
    if (loaded_model && loaded_model_path == path) {
        return loaded_model;
    }

    NSString* model_path = [NSString stringWithUTF8String:path.c_str()];
    if (!model_path) {
        error_message = "Core MLモデルのパスをUTF-8として解釈できません。";
        return nil;
    }

    MLModelConfiguration* configuration = [MLModelConfiguration new];
    configuration.computeUnits = MLComputeUnitsAll;

    NSError* error = nil;
    MLModel* model = [MLModel
        modelWithContentsOfURL:[NSURL fileURLWithPath:model_path]
        configuration:configuration
        error:&error
    ];
    if (!model) {
        error_message = describe_error(@"Core MLモデルを読み込めません", error);
        return nil;
    }

    loaded_model = model;
    loaded_model_path = path;
    return loaded_model;
}

MLMultiArray* make_multi_array(
    float* data,
    NSArray<NSNumber*>* shape,
    NSArray<NSNumber*>* strides,
    NSError** error
) {
    return [[MLMultiArray alloc]
        initWithDataPointer:data
        shape:shape
        dataType:MLMultiArrayDataTypeFloat32
        strides:strides
        deallocator:nil
        error:error
    ];
}

bool copy_multi_array(
    MLMultiArray* array,
    size_t expected_count,
    std::vector<float>& output,
    std::string& error_message
) {
    if (!array || static_cast<size_t>(array.count) != expected_count) {
        error_message = "Core MLモデルの出力要素数が想定と一致しません。";
        return false;
    }

    output.resize(expected_count);
    if (array.dataType == MLMultiArrayDataTypeFloat32) {
        const auto* source = static_cast<const float*>(array.dataPointer);
        std::copy_n(source, expected_count, output.begin());
        return true;
    }
    if (array.dataType == MLMultiArrayDataTypeDouble) {
        const auto* source = static_cast<const double*>(array.dataPointer);
        std::transform(
            source,
            source + expected_count,
            output.begin(),
            [](double value) { return static_cast<float>(value); }
        );
        return true;
    }

    error_message = "Core MLモデルの出力型がFloat32またはDoubleではありません。";
    return false;
}

struct PolicyMove {
    YaneuraOu::Move move;
    float policy;
    float logit;
};

bool evaluate(
    const char* sfen,
    const char* compiled_model_path,
    int top_n,
    float& value,
    std::vector<PolicyMove>& result,
    std::string& error_message
) {
    using namespace YaneuraOu;
    using namespace YaneuraOu::Eval::dlshogi;

    ENGINE_RUNTIME::ensure_engine_primitives_initialized();

    StateInfo state;
    Position position;
    if (auto position_error = position.set(sfen, &state, true)) {
        error_message = std::string("SFENを読み込めません: ") + position_error->what();
        return false;
    }

    MLModel* model = load_model(compiled_model_path, error_message);
    if (!model) {
        return false;
    }

    std::vector<PType> packed_input1(packed_input1_byte_count(1), 0);
    std::vector<PType> packed_input2(packed_input2_byte_count(1), 0);
    std::vector<NN_Input1> input1(input1_element_count(1), 0.0f);
    std::vector<NN_Input2> input2(input2_element_count(1), 0.0f);
    make_input_features(
        position,
        0,
        packed_input1.data(),
        packed_input2.data()
    );
    extract_input_features(
        1,
        packed_input1.data(),
        packed_input2.data(),
        input1.data(),
        input2.data()
    );

    NSError* error = nil;
    MLMultiArray* model_input1 = make_multi_array(
        input1.data(),
        @[@1, @62, @9, @9],
        @[@5022, @81, @9, @1],
        &error
    );
    if (!model_input1) {
        error_message = describe_error(@"Core ML入力1を作成できません", error);
        return false;
    }
    MLMultiArray* model_input2 = make_multi_array(
        input2.data(),
        @[@1, @57, @9, @9],
        @[@4617, @81, @9, @1],
        &error
    );
    if (!model_input2) {
        error_message = describe_error(@"Core ML入力2を作成できません", error);
        return false;
    }

    MLDictionaryFeatureProvider* provider = [[MLDictionaryFeatureProvider alloc]
        initWithDictionary:@{
            @"input1": [MLFeatureValue featureValueWithMultiArray:model_input1],
            @"input2": [MLFeatureValue featureValueWithMultiArray:model_input2],
        }
        error:&error
    ];
    if (!provider) {
        error_message = describe_error(@"Core ML入力を設定できません", error);
        return false;
    }

    id<MLFeatureProvider> prediction = [model
        predictionFromFeatures:provider
        options:[MLPredictionOptions new]
        error:&error
    ];
    if (!prediction) {
        error_message = describe_error(@"Core ML推論に失敗しました", error);
        return false;
    }

    std::vector<float> policy_logits;
    if (!copy_multi_array(
            [prediction featureValueForName:@"output_policy"].multiArrayValue,
            MAX_MOVE_LABEL_NUM * static_cast<size_t>(SQ_NB),
            policy_logits,
            error_message
        )) {
        return false;
    }

    std::vector<float> value_output;
    if (!copy_multi_array(
            [prediction featureValueForName:@"output_value"].multiArrayValue,
            1,
            value_output,
            error_message
        )) {
        return false;
    }
    value = value_output[0];

    std::vector<std::pair<Move, float>> legal_logits;
    for (Move move : MoveList<LEGAL>(position)) {
        const int label = make_move_label(move, position.side_to_move());
        legal_logits.emplace_back(move, policy_logits[static_cast<size_t>(label)]);
    }
    if (legal_logits.empty()) {
        result.clear();
        return true;
    }

    const float maximum = std::max_element(
        legal_logits.begin(),
        legal_logits.end(),
        [](const auto& lhs, const auto& rhs) { return lhs.second < rhs.second; }
    )->second;
    double total = 0.0;
    for (const auto& candidate : legal_logits) {
        total += std::exp(
            static_cast<double>(candidate.second - maximum)
            / policy_softmax_temperature
        );
    }
    if (!std::isfinite(total) || total <= 0.0) {
        error_message = "Policyのsoftmaxを正規化できません。";
        return false;
    }

    result.clear();
    result.reserve(legal_logits.size());
    for (const auto& candidate : legal_logits) {
        const float probability = static_cast<float>(
            std::exp(
                static_cast<double>(candidate.second - maximum)
                / policy_softmax_temperature
            ) / total
        );
        result.push_back({candidate.first, probability, candidate.second});
    }
    std::sort(result.begin(), result.end(), [](const auto& lhs, const auto& rhs) {
        if (lhs.policy != rhs.policy) {
            return lhs.policy > rhs.policy;
        }
        return lhs.move.to_u16() < rhs.move.to_u16();
    });
    if (top_n > 0 && result.size() > static_cast<size_t>(top_n)) {
        result.resize(static_cast<size_t>(top_n));
    }
    return true;
}

}  // namespace

extern "C" int kifulens_native_policy_value(
    const char* sfen,
    const char* compiled_model_path,
    int top_n,
    float* value,
    kifulens_policy_move* moves,
    int move_capacity,
    char* error_message,
    int error_message_capacity
) {
    if (!sfen || !compiled_model_path || !value || !moves || move_capacity <= 0) {
        write_error(
            error_message,
            error_message_capacity,
            "policy/value APIの引数が不足しています。"
        );
        return -1;
    }

    std::lock_guard<std::mutex> lock(policy_value_mutex);
    @autoreleasepool {
        std::vector<PolicyMove> result;
        std::string error;
        float evaluated_value = 0.0f;
        if (!evaluate(
                sfen,
                compiled_model_path,
                std::min(top_n, move_capacity),
                evaluated_value,
                result,
                error
            )) {
            write_error(error_message, error_message_capacity, error);
            return -1;
        }

        const int count = std::min(
            static_cast<int>(result.size()),
            move_capacity
        );
        *value = evaluated_value;
        for (int index = 0; index < count; ++index) {
            const std::string usi = YaneuraOu::to_usi_string(result[index].move);
            std::snprintf(
                moves[index].usi,
                KIFULENS_POLICY_USI_CAPACITY,
                "%s",
                usi.c_str()
            );
            moves[index].policy = result[index].policy;
            moves[index].logit = result[index].logit;
        }
        if (error_message && error_message_capacity > 0) {
            error_message[0] = '\0';
        }
        return count;
    }
}
