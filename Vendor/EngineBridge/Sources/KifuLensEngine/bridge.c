#include "kifulens_engine.h"

// 探索とPolicyを同じpackage productへ取り込み、共通データを二重化しない。
int kifulens_engine_start(
    const char* engine_id, kifulens_usi_read_cb read,
    kifulens_usi_write_cb write, kifulens_exit_cb did_exit,
    void* context, const char* engine_directory
) {
    return kifulens_native_start(engine_id, read, write, did_exit, context, engine_directory);
}

int kifulens_policy_value(
    const char* sfen, const char* model_path, int top_n,
    float* value, kifulens_policy_move* moves, int capacity,
    char* error, int error_capacity
) {
    return kifulens_native_policy_value(sfen, model_path, top_n, value, moves, capacity, error, error_capacity);
}
