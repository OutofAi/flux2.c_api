import os, time, ctypes
import gradio as gr

try:
    LIB = os.path.abspath("libfluxserver.so")
    lib = ctypes.CDLL(LIB)
except:
    LIB = os.path.abspath("libfluxserver.dylib")
    lib = ctypes.CDLL(LIB)  

class FluxParams(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("num_steps", ctypes.c_int),
        ("guidance_scale", ctypes.c_float),
        ("seed", ctypes.c_longlong),
        ("strength", ctypes.c_float),
    ]

lib.flux_engine_create.argtypes = [ctypes.c_char_p, ctypes.c_int]
lib.flux_engine_create.restype  = ctypes.c_void_p

lib.flux_engine_destroy.argtypes = [ctypes.c_void_p]
lib.flux_engine_destroy.restype  = None

lib.flux_engine_txt2img_to_file.argtypes = [
    ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(FluxParams), ctypes.c_char_p
]
lib.flux_engine_txt2img_to_file.restype = ctypes.c_int

lib.flux_engine_last_error.argtypes = [ctypes.c_void_p]
lib.flux_engine_last_error.restype = ctypes.c_char_p

ENGINE = None

def get_engine(model_dir, use_mmap):
    global ENGINE
    if ENGINE:
        return ENGINE
    ENGINE = lib.flux_engine_create(model_dir.encode("utf-8"), int(use_mmap))
    if not ENGINE:
        raise RuntimeError("Failed to create engine (check model path / deps).")
    return ENGINE

def generate(model_dir, prompt, width, height, steps, guidance, seed, use_mmap):
    e = get_engine(model_dir, use_mmap)
    out = f"/tmp/flux_{int(time.time()*1000)}.png"
    p = FluxParams(width, height, steps, float(guidance), int(seed), 0.75)
    rc = lib.flux_engine_txt2img_to_file(e, prompt.encode("utf-8"), ctypes.byref(p), out.encode("utf-8"))
    if rc != 0:
        err = lib.flux_engine_last_error(e).decode("utf-8", errors="ignore")
        raise RuntimeError(err or f"Generation failed (rc={rc})")
    return out

with gr.Blocks() as demo:
    gr.Markdown("# FLUX (persistent model)")

    model_dir = gr.Textbox(value="flux-klein-model", label="Model dir")
    prompt = gr.Textbox(value="A fluffy orange cat sitting on a windowsill", label="Prompt")
    width = gr.Slider(64, 1024, value=256, step=64, label="Width")
    height = gr.Slider(64, 1024, value=256, step=64, label="Height")
    steps = gr.Slider(1, 50, value=4, step=1, label="Steps")
    guidance = gr.Slider(0.0, 10.0, value=1.0, step=0.1, label="Guidance")
    seed = gr.Number(value=-1, label="Seed (-1 random)", precision=0)
    use_mmap = gr.Checkbox(value=False, label="Use mmap (lower RAM, slower)")

    btn = gr.Button("Generate")
    out_img = gr.Image(label="Output")

    btn.click(generate, inputs=[model_dir, prompt, width, height, steps, guidance, seed, use_mmap], outputs=out_img)

demo.queue(1)
demo.launch(debug=True)
