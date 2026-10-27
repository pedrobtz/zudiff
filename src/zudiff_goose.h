#pragma once
#include <stdint.h>
typedef struct gs_stack gs_stack;
#pragma pack(push, 1)
typedef struct { uint8_t *base; int64_t len; } gs_rhdr;
typedef struct { gs_rhdr *hdr; gs_stack *stk; } gs_rref;
typedef struct { gs_rhdr *hdr; gs_stack *stk; gs_rhdr *fl; gs_stack *flstk; } gs_pref;

typedef struct { int32_t *data; int64_t len; } sl_i32;

typedef struct { int64_t e[3]; } a3_i64;

typedef struct { uint8_t *data; int64_t len; } sl_u8;

#pragma pack(pop)

#ifdef __cplusplus
extern "C" {
#endif
void goose_init(int argc, char **argv);
int64_t zudiff_probe_index(int64_t gs_export_arg0);
int64_t zudiff_probe_sum(sl_i32 gs_export_arg0_2);
#ifdef __cplusplus
}
#endif
