#include "bitboard.h"
#include "engine.h"
#include "misc.h"
#include "position.h"
#include "usi.h"
#include "engine/yaneuraou-engine/yaneuraou-search.h"
#if defined(KIFULENS_HAS_POLICY)
#include "eval/deep/nn_types.h"
#endif
#include "ios_runtime.h"

#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>

namespace ENGINE_RUNTIME {

void ensure_engine_primitives_initialized() {
    static std::once_flag initialization;
    std::call_once(initialization, [] {
        YaneuraOu::Bitboards::init();
        YaneuraOu::Position::init();
#if defined(KIFULENS_HAS_POLICY)
        YaneuraOu::Eval::dlshogi::set_model_architecture(
            YaneuraOu::Eval::dlshogi::MODEL_ARCHITECTURE_WCSC28
        );
        YaneuraOu::Eval::dlshogi::init();
#endif
    });
}

}  // namespace ENGINE_RUNTIME

namespace {

class CallbackOutputBuffer final : public std::streambuf {
public:
    explicit CallbackOutputBuffer(KifuLensSession session)
        : session_(session) {}

protected:
    int_type overflow(int_type character = traits_type::eof()) override {
        if (session_.write && !traits_type::eq_int_type(character, traits_type::eof())) {
            session_.write(session_.context, static_cast<int>(character));
        }
        return traits_type::not_eof(character);
    }

private:
    KifuLensSession session_;
};

class CallbackInputBuffer final : public std::streambuf {
public:
    explicit CallbackInputBuffer(KifuLensSession session)
        : session_(session) {}

protected:
    int_type underflow() override {
        if (!session_.read) {
            return traits_type::eof();
        }
        if (next_character_ == traits_type::eof()) {
            next_character_ = session_.read(session_.context);
        }
        return next_character_;
    }

    int_type uflow() override {
        const auto character = underflow();
        next_character_ = traits_type::eof();
        return character;
    }

private:
    KifuLensSession session_;
    int_type next_character_ = traits_type::eof();
};

void run_engine(
    KifuLensSession session,
    std::string engine_directory
) {
    CallbackOutputBuffer output_buffer(session);
    CallbackInputBuffer input_buffer(session);
    auto* previous_output = std::cout.rdbuf(&output_buffer);
    auto* previous_input = std::cin.rdbuf(&input_buffer);

    if (engine_directory.empty()) {
        engine_directory = ".";
    }
    auto executable_path = engine_directory + "/KifuLensEngine-iOS";
    int argument_count = 1;
    char* arguments[] = {executable_path.data()};

    YaneuraOu::CommandLine::g.set_arg(argument_count, arguments);
    ENGINE_RUNTIME::ensure_engine_primitives_initialized();

    {
        auto engine = std::make_unique<YaneuraOu::Search::YaneuraOuEngine>();
        auto usi = std::make_unique<YaneuraOu::USIEngine>();
        usi->set_engine(*engine);
        usi->enqueue_startup_commands(YaneuraOu::CommandLine::g);
        usi->loop();
    }

    std::cout.rdbuf(previous_output);
    std::cin.rdbuf(previous_input);
    kifulens_session_finished(session);
}

}  // namespace

extern "C" int ENGINE_ENTRY(KifuLensSession session, const char* engine_directory) {
    std::thread thread(run_engine, session, std::string(engine_directory ? engine_directory : "."));
    thread.detach();
    return 0;
}
