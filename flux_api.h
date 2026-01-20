#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct flux_engine flux_engine;

typedef struct {
    int width;
    int height;
    int num_steps;
    float guidance_scale;
    int64_t seed;      // -1 random
    float strength;    // for img2img
} flux_params_c;

flux_engine* flux_engine_create(const char *model_dir, int use_mmap);
void         flux_engine_destroy(flux_engine *e);

// Returns 0 on success, nonzero on failure. Use flux_engine_last_error for details.
int  flux_engine_txt2img_to_file(flux_engine *e,
                                 const char *prompt,
                                 const flux_params_c *p,
                                 const char *out_path);

int  flux_engine_img2img_to_file(flux_engine *e,
                                 const char *prompt,
                                 const char *in_path,
                                 const flux_params_c *p,
                                 const char *out_path);

const char* flux_engine_last_error(flux_engine *e);

#ifdef __cplusplus
}
#endif
