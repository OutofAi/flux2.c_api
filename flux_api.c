#include "flux_api.h"
#include "flux.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct flux_engine {
    flux_ctx *ctx;
    char last_err[1024];
};

static void set_err(flux_engine *e, const char *msg) {
    if (!e) return;
    strncpy(e->last_err, msg ? msg : "unknown error", sizeof(e->last_err) - 1);
    e->last_err[sizeof(e->last_err) - 1] = '\0';
}

flux_engine* flux_engine_create(const char *model_dir, int use_mmap) {
    flux_engine *e = (flux_engine*)calloc(1, sizeof(flux_engine));
    if (!e) return NULL;

    e->last_err[0] = '\0';
    e->ctx = flux_load_dir(model_dir);
    if (!e->ctx) {
        set_err(e, flux_get_error());
        free(e);
        return NULL;
    }
    if (use_mmap) {
        flux_set_mmap(e->ctx, 1);
    }
    return e;
}

void flux_engine_destroy(flux_engine *e) {
    if (!e) return;
    if (e->ctx) flux_free(e->ctx);
    free(e);
}

const char* flux_engine_last_error(flux_engine *e) {
    if (!e) return "engine is NULL";
    return e->last_err[0] ? e->last_err : "";
}

static int64_t choose_seed(int64_t seed) {
    if (seed >= 0) return seed;
    return (int64_t)time(NULL);
}

int flux_engine_txt2img_to_file(flux_engine *e,
                                const char *prompt,
                                const flux_params_c *p,
                                const char *out_path) {
    if (!e || !e->ctx) return 1;
    if (!prompt || !out_path || !p) { set_err(e, "bad args"); return 2; }

    flux_params params = {
        .width = p->width,
        .height = p->height,
        .num_steps = p->num_steps,
        .guidance_scale = p->guidance_scale,
        .seed = p->seed,
        .strength = p->strength
    };

    int64_t s = choose_seed(params.seed);
    flux_set_seed(s);

    flux_image *img = flux_generate(e->ctx, prompt, &params);
    if (!img) { set_err(e, flux_get_error()); return 3; }

    int rc = flux_image_save_with_seed(img, out_path, s);
    flux_image_free(img);

    if (rc != 0) { set_err(e, "failed to save output"); return 4; }
    return 0;
}

int flux_engine_img2img_to_file(flux_engine *e,
                                const char *prompt,
                                const char *in_path,
                                const flux_params_c *p,
                                const char *out_path) {
    if (!e || !e->ctx) return 1;
    if (!in_path || !out_path || !p) { set_err(e, "bad args"); return 2; }

    flux_params params = {
        .width = p->width,
        .height = p->height,
        .num_steps = p->num_steps,
        .guidance_scale = p->guidance_scale,
        .seed = p->seed,
        .strength = p->strength
    };

    int64_t s = choose_seed(params.seed);
    flux_set_seed(s);

    flux_image *in = flux_image_load(in_path);
    if (!in) { set_err(e, "failed to load input image"); return 3; }

    // Optional: adopt input dims if caller passed 0
    if (params.width <= 0)  params.width  = in->width;
    if (params.height <= 0) params.height = in->height;

    flux_image *img = flux_img2img(e->ctx, prompt, in, &params);
    flux_image_free(in);

    if (!img) { set_err(e, flux_get_error()); return 4; }

    int rc = flux_image_save_with_seed(img, out_path, s);
    flux_image_free(img);

    if (rc != 0) { set_err(e, "failed to save output"); return 5; }
    return 0;
}
