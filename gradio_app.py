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

css = """
    /* Make the row behave nicely */
    #controls-row {
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: nowrap; /* or wrap if you prefer on small screens */
    }
    /* Stop these components from stretching */
    #controls-row > * {
    flex: 0 0 auto !important;
    width: auto !important;
    min-width: 0 !important;
    }
    /* Same idea for your radio HTML blocks (optional but helps) */
    #radioanimated_duration,
    #radioanimated_duration > div,
    #radioanimated_resolution,
    #radioanimated_resolution > div {
    width: fit-content !important;
    }
    
    #col-container {
        margin: 0 auto;
        max-width: 1600px;
    }
    #modal-container {
    width: 100vw;            /* Take full viewport width */
    height: 100vh;           /* Take full viewport height (optional) */
    display: flex;           
    justify-content: center; /* Center content horizontally */
    align-items: center;     /* Center content vertically if desired */
    }
    #modal-content {
    width: 100%;
    max-width: 700px;         /* Limit content width */
    margin: 0 auto;
    border-radius: 8px;
    padding: 1.5rem;
    }
    #step-column {
        padding: 10px;
        border-radius: 8px;
        box-shadow: var(--card-shadow);
        margin: 10px;
    }
    #col-showcase {
        margin: 0 auto;
        max-width: 1100px;
    }
    .button-gradient {
        background: linear-gradient(45deg, rgb(255, 65, 108), rgb(255, 75, 43), rgb(255, 155, 0), rgb(255, 65, 108)) 0% 0% / 400% 400%;
        border: none;
        padding: 14px 28px;
        font-size: 16px;
        font-weight: bold;
        color: white;
        border-radius: 10px;
        cursor: pointer;
        transition: 0.3s ease-in-out;
        animation: 2s linear 0s infinite normal none running gradientAnimation;
        box-shadow: rgba(255, 65, 108, 0.6) 0px 4px 10px;
    }
    .toggle-container {
    display: inline-flex;
    background-color: #ffd6ff;  /* light pink background */
    border-radius: 9999px;
    padding: 4px;
    position: relative;
    width: fit-content;
    font-family: sans-serif;
    }
    .toggle-container input[type="radio"] {
    display: none;
    }
    .toggle-container label {
    position: relative;
    z-index: 2;
    flex: 1;
    text-align: center;
    font-weight: 700;
    color: #4b2ab5; /* dark purple text for unselected */
    padding: 6px 22px;
    border-radius: 9999px;
    cursor: pointer;
    transition: color 0.25s ease;
    }
    /* Moving highlight */
    .toggle-highlight {
    position: absolute;
    top: 4px;
    left: 4px;
    width: calc(50% - 4px);
    height: calc(100% - 8px);
    background-color: #4b2ab5; /* dark purple background */
    border-radius: 9999px;
    transition: transform 0.25s ease;
    z-index: 1;
    }
    /* When "True" is checked */
    #true:checked ~ label[for="true"] {
    color: #ffd6ff; /* light pink text */
    }
    /* When "False" is checked */
    #false:checked ~ label[for="false"] {
    color: #ffd6ff; /* light pink text */
    }
    /* Move highlight to right side when False is checked */
    #false:checked ~ .toggle-highlight {
    transform: translateX(100%);
    }
    """

with gr.Blocks() as demo:
    gr.Markdown("# FLUX (persistent model)")

    with gr.Column(elem_id="col-container"):
        with gr.Row():
            with gr.Column(elem_id="step-column"):
                prompt = gr.Textbox(value="a man eating a burger that the letter A is written on it", label="Prompt")
                out_img = gr.Image(label="Output", height=512)
                btn = gr.Button("Generate", variant="primary", elem_classes="button-gradient")
                
            with gr.Column(elem_id="step-column"):
                model_dir = gr.Textbox(value="flux-klein-model", label="Model dir")
                
                width = gr.Slider(64, 1024, value=256, step=64, label="Width")
                height = gr.Slider(64, 1024, value=256, step=64, label="Height")
                steps = gr.Slider(1, 50, value=4, step=1, label="Steps")
                guidance = gr.Slider(0.0, 10.0, value=1.0, step=0.1, label="Guidance")
                seed = gr.Number(value=-1, label="Seed (-1 random)", precision=0)
                use_mmap = gr.Checkbox(value=False, label="Use mmap (lower RAM, slower)")





    btn.click(generate, inputs=[model_dir, prompt, width, height, steps, guidance, seed, use_mmap], outputs=out_img)

demo.queue(1)
demo.launch(debug=True, css=css)
