#ifndef KIFULENS_IOS_RUNTIME_H
#define KIFULENS_IOS_RUNTIME_H
#include "kifulens_engine.h"

struct KifuLensSession {
    kifulens_usi_read_cb read;
    kifulens_usi_write_cb write;
    kifulens_exit_cb did_exit;
    void* context;
};

// 全エンジンで一つのregistryが起動状態を管理する。
void kifulens_session_finished(const KifuLensSession& session);

#ifdef ENGINE_RUNTIME
namespace ENGINE_RUNTIME {
void ensure_engine_primitives_initialized();
}
#endif
#endif
