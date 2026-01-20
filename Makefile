# FLUX.2 klein 4B - Pure C Inference Engine
# Makefile

CC = gcc
CFLAGS_BASE = -Wall -Wextra -O3 -march=native -ffast-math
LDFLAGS = -lm

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Source files
SRCS = flux.c flux_kernels.c flux_tokenizer.c flux_vae.c flux_transformer.c flux_sample.c flux_image.c flux_safetensors.c flux_qwen3.c flux_qwen3_tokenizer.c
OBJS = $(SRCS:.c=.o)
MAIN = main.c
TARGET = flux
LIB = libflux.a

# Debug build flags
DEBUG_CFLAGS = -Wall -Wextra -g -O0 -DDEBUG -fsanitize=address

# Shared library (for Python/Gradio integration)
SHARED_SRCS = flux_api.c
SHARED_OBJS = $(SHARED_SRCS:.c=.o)

# Platform-specific shared library name and flags
ifeq ($(UNAME_S),Darwin)
SHLIB = libfluxserver.dylib
SHLIB_LDFLAGS = -dynamiclib
else
SHLIB = libfluxserver.so
SHLIB_LDFLAGS = -shared -Wl,--no-undefined
endif

.PHONY: all clean debug lib install info test pngtest help generic blas mps generic-so blas-so mps-so

# Default: show available targets
all: help

help:
	@echo "FLUX.2 klein 4B - Build Targets"
	@echo ""
	@echo "Choose a backend:"
	@echo "  make generic  - Pure C, no dependencies (slow)"
	@echo "  make blas     - With BLAS acceleration (~30x faster)"
ifeq ($(UNAME_S),Darwin)
ifeq ($(UNAME_M),arm64)
	@echo "  make mps      - Apple Silicon with Metal GPU (fastest)"
endif
endif
	@echo ""
	@echo "Other targets:"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make test     - Run inference test"
	@echo "  make pngtest  - Compare PNG load on compressed image"
	@echo "  make info     - Show build configuration"
	@echo "  make lib      - Build static library"
	@echo "  make blas-so  - Build shared library for Python/Gradio"
	@echo "  make generic-so - Build shared library (generic)"
	@echo "  make mps-so     - Build shared library (Metal, macOS arm64)"
	@echo ""
	@echo "Example: make mps && ./flux -d flux-klein-model -p \"a cat\" -o cat.png"

# =============================================================================
# Backend: generic (pure C, no BLAS)
# =============================================================================
generic: CFLAGS = $(CFLAGS_BASE) -DGENERIC_BUILD
generic: clean $(TARGET)
	@echo ""
	@echo "Built with GENERIC backend (pure C, no BLAS)"
	@echo "This will be slow but has zero dependencies."

# =============================================================================
# Backend: blas (Accelerate on macOS, OpenBLAS on Linux)
# =============================================================================
ifeq ($(UNAME_S),Darwin)
blas: CFLAGS = $(CFLAGS_BASE) -DUSE_BLAS -DACCELERATE_NEW_LAPACK
blas: LDFLAGS += -framework Accelerate
else
blas: CFLAGS = $(CFLAGS_BASE) -DUSE_BLAS -DUSE_OPENBLAS -I/usr/include/openblas
blas: LDFLAGS += -lopenblas
endif
blas: clean $(TARGET)
	@echo ""
	@echo "Built with BLAS backend (~30x faster than generic)"

# =============================================================================
# Backend: mps (Apple Silicon Metal GPU)
# =============================================================================
ifeq ($(UNAME_S),Darwin)
ifeq ($(UNAME_M),arm64)
MPS_CFLAGS = $(CFLAGS_BASE) -DUSE_BLAS -DUSE_METAL -DACCELERATE_NEW_LAPACK
MPS_OBJCFLAGS = $(MPS_CFLAGS) -fobjc-arc
MPS_LDFLAGS = $(LDFLAGS) -framework Accelerate -framework Metal -framework MetalPerformanceShaders -framework Foundation

mps: clean mps-build
	@echo ""
	@echo "Built with MPS backend (Metal GPU acceleration)"

mps-build: $(SRCS:.c=.mps.o) flux_metal.o main.mps.o
	$(CC) $(MPS_CFLAGS) -o $(TARGET) $^ $(MPS_LDFLAGS)

%.mps.o: %.c flux.h flux_kernels.h
	$(CC) $(MPS_CFLAGS) -c -o $@ $<

flux_metal.o: flux_metal.m flux_metal.h
	$(CC) $(MPS_OBJCFLAGS) -c -o $@ $<

else
mps:
	@echo "Error: MPS backend requires Apple Silicon (arm64)"
	@exit 1
endif
else
mps:
	@echo "Error: MPS backend requires macOS"
	@exit 1
endif

# =============================================================================
# Build rules
# =============================================================================
$(TARGET): $(OBJS) main.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

lib: $(LIB)

$(LIB): $(OBJS)
	ar rcs $@ $^

%.o: %.c flux.h flux_kernels.h
	$(CC) $(CFLAGS) -c -o $@ $<

# Debug build
debug: CFLAGS = $(DEBUG_CFLAGS)
debug: LDFLAGS += -fsanitize=address
debug: clean $(TARGET)

# =============================================================================
# Shared library build (persistent engine for Python/Gradio)
# =============================================================================

# Ensure objects for shared lib are PIC
%.pic.o: %.c flux.h flux_kernels.h
	$(CC) $(CFLAGS) -fPIC -c -o $@ $<

SHARED_PIC_OBJS = $(OBJS:.o=.pic.o) $(SHARED_SRCS:.c=.pic.o)

$(SHLIB): $(SHARED_PIC_OBJS)
	$(CC) $(CFLAGS) $(SHLIB_LDFLAGS) -o $@ $^ $(LDFLAGS)

generic-so: CFLAGS = $(CFLAGS_BASE) -DGENERIC_BUILD
generic-so: clean $(SHLIB)
	@echo ""
	@echo "Built shared library: $(SHLIB) (GENERIC backend)"

ifeq ($(UNAME_S),Darwin)
blas-so: CFLAGS = $(CFLAGS_BASE) -DUSE_BLAS -DACCELERATE_NEW_LAPACK
blas-so: LDFLAGS += -framework Accelerate
else
blas-so: CFLAGS = $(CFLAGS_BASE) -DUSE_BLAS -DUSE_OPENBLAS -I/usr/include/openblas
blas-so: LDFLAGS += -lopenblas
endif
blas-so: clean $(SHLIB)
	@echo ""
	@echo "Built shared library: $(SHLIB) (BLAS backend)"

# macOS Apple Silicon Metal shared lib
ifeq ($(UNAME_S),Darwin)
ifeq ($(UNAME_M),arm64)
mps-so: clean mps-so-build
	@echo ""
	@echo "Built shared library: $(SHLIB) (MPS backend)"

mps-so-build: $(SRCS:.c=.mps.pic.o) flux_metal.o $(SHARED_SRCS:.c=.mps.pic.o)
	$(CC) $(MPS_CFLAGS) -o $(SHLIB) $^ $(MPS_LDFLAGS) -dynamiclib

%.mps.pic.o: %.c flux.h flux_kernels.h
	$(CC) $(MPS_CFLAGS) -fPIC -c -o $@ $<

else
mps-so:
	@echo "Error: MPS shared library requires Apple Silicon (arm64)"
	@exit 1
endif
else
mps-so:
	@echo "Error: MPS shared library requires macOS"
	@exit 1
endif

# =============================================================================
# Test and utilities
# =============================================================================
TEST_PROMPT = "A fluffy orange cat sitting on a windowsill"
test:
	@echo "Running inference test..."
	@./$(TARGET) -d flux-klein-model -p $(TEST_PROMPT) --seed 42 --steps 1 -o /tmp/flux_test_output.png -W 64 -H 64
	@python3 -c "\
import numpy as np; \
from PIL import Image; \
ref = np.array(Image.open('test_vectors/reference_1step_64x64_seed42.png')); \
test = np.array(Image.open('/tmp/flux_test_output.png')); \
diff = np.abs(ref.astype(float) - test.astype(float)); \
print(f'Max diff: {diff.max()}, Mean diff: {diff.mean():.4f}'); \
exit(0 if diff.max() < 2 else 1)"
	@rm -f /tmp/flux_test_output.png
	@echo "TEST PASSED"

pngtest:
	@echo "Running PNG compression compare test..."
	@$(CC) $(CFLAGS_BASE) -I. png_compare.c flux_image.c -lm -o /tmp/flux_png_compare
	@/tmp/flux_png_compare images/woman_with_sunglasses.png images/woman_with_sunglasses_compressed2.png
	@/tmp/flux_png_compare images/cat_uncompressed.png images/cat_compressed.png
	@rm -f /tmp/flux_png_compare
	@echo "PNG TEST PASSED"

install: $(TARGET) $(LIB)
	install -d /usr/local/bin
	install -d /usr/local/lib
	install -d /usr/local/include
	install -m 755 $(TARGET) /usr/local/bin/
	install -m 644 $(LIB) /usr/local/lib/
	install -m 644 flux.h /usr/local/include/
	install -m 644 flux_kernels.h /usr/local/include/

clean:
	rm -f $(OBJS) *.mps.o *.pic.o *.mps.pic.o flux_metal.o main.o $(TARGET) $(LIB) $(SHLIB)

info:
	@echo "Platform: $(UNAME_S) $(UNAME_M)"
	@echo "Compiler: $(CC)"
	@echo ""
	@echo "Available backends for this platform:"
	@echo "  generic - Pure C (always available)"
ifeq ($(UNAME_S),Darwin)
	@echo "  blas    - Apple Accelerate"
ifeq ($(UNAME_M),arm64)
	@echo "  mps     - Metal GPU (recommended)"
endif
else
	@echo "  blas    - OpenBLAS (requires libopenblas-dev)"
endif

# =============================================================================
# Dependencies
# =============================================================================
flux.o: flux.c flux.h flux_kernels.h flux_safetensors.h flux_qwen3.h
flux_kernels.o: flux_kernels.c flux_kernels.h
flux_tokenizer.o: flux_tokenizer.c flux.h
flux_vae.o: flux_vae.c flux.h flux_kernels.h
flux_transformer.o: flux_transformer.c flux.h flux_kernels.h
flux_sample.o: flux_sample.c flux.h flux_kernels.h
flux_image.o: flux_image.c flux.h
flux_safetensors.o: flux_safetensors.c flux_safetensors.h
flux_qwen3.o: flux_qwen3.c flux_qwen3.h flux_safetensors.h
flux_qwen3_tokenizer.o: flux_qwen3_tokenizer.c flux_qwen3.h
flux_api.o: flux_api.c flux_api.h flux.h
flux_api.pic.o: flux_api.c flux_api.h flux.h
flux_api.mps.pic.o: flux_api.c flux_api.h flux.h
main.o: main.c flux.h flux_kernels.h
