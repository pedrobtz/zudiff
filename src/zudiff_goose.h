#pragma once
#include <stdint.h>
typedef struct gs_stack gs_stack;
#pragma pack(push, 1)
typedef struct { uint8_t *base; int64_t len; } gs_rhdr;
typedef struct { gs_rhdr *hdr; gs_stack *stk; } gs_rref;
typedef struct { gs_rhdr *hdr; gs_stack *stk; gs_rhdr *fl; gs_stack *flstk; } gs_pref;

typedef struct { int32_t *data; int64_t len; } sl_i32;

typedef struct { uint8_t *data; int64_t len; } sl_u8;

typedef struct Run_g Run_g;
struct Run_g {
    int32_t op_g;
    int32_t o_g;
    int32_t n_g;
    int32_t len_g;
};

typedef struct Step_g Step_g;
struct Step_g {
    int32_t op_g;
    int32_t len_g;
};

typedef struct { int64_t e[3]; } a3_i64;

#pragma pack(pop)

#ifdef __cplusplus
extern "C" {
#endif
void goose_init(int argc, char **argv);
int64_t zudiff_probe_index(int64_t gs_export_arg0);
int64_t zudiff_probe_sum(sl_i32 gs_export_arg0_2);
int64_t zudiff_probe_stack(int64_t gs_export_arg0_3, uint8_t gs_export_arg1);
const uint8_t * zudiff_diff_ids(sl_i32 gs_export_arg0_4, sl_i32 gs_export_arg1_2, int32_t gs_export_arg2, int64_t gs_export_arg3, int64_t *gs_export_len_4);
const uint8_t * zudiff_diff_bytes(sl_u8 gs_export_arg0_5, sl_u8 gs_export_arg1_3, int32_t gs_export_arg2_2, int64_t gs_export_arg3_2, int64_t *gs_export_len_5);
#ifdef __cplusplus
}
#endif
