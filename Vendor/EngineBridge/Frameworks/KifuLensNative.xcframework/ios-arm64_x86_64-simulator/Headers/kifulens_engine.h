#ifndef KIFULENS_ENGINE_H
#define KIFULENS_ENGINE_H

typedef int (*kifulens_usi_read_cb)(void* context);
typedef void (*kifulens_usi_write_cb)(void* context, int byte);
typedef void (*kifulens_exit_cb)(void* context);

#define KIFULENS_POLICY_USI_CAPACITY 8

typedef struct kifulens_policy_move {
    char usi[KIFULENS_POLICY_USI_CAPACITY];
    float policy;
    float logit;
} kifulens_policy_move;

#ifdef __cplusplus
extern "C" {
#endif

int kifulens_engine_start(
    const char* engine_id, kifulens_usi_read_cb read,
    kifulens_usi_write_cb write, kifulens_exit_cb did_exit,
    void* context, const char* engine_directory
);
int kifulens_policy_value(
    const char* sfen, const char* model_path, int top_n,
    float* value, kifulens_policy_move* moves, int capacity,
    char* error, int error_capacity
);

// Swift PackageのC接続部が参照するnative実装。
int kifulens_native_start(
    const char* engine_id, kifulens_usi_read_cb read,
    kifulens_usi_write_cb write, kifulens_exit_cb did_exit,
    void* context, const char* engine_directory
);
int kifulens_native_policy_value(
    const char* sfen, const char* model_path, int top_n,
    float* value, kifulens_policy_move* moves, int capacity,
    char* error, int error_capacity
);

#ifdef __cplusplus
}
#endif
#endif
