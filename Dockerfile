# ==============================================================================
# Stage 1: Build Engine & Native FFI Binaries
# ==============================================================================
FROM nvidia/cuda:12.1.0-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    python3-dev \
    python3-pip \
    git \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy requirements and install python dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy source files and compile native layers / C++ bindings
COPY . .
RUN python3 setup.py build_ext --inplace

# ==============================================================================
# Stage 2: Secure Runtime Image
# ==============================================================================
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV KUBU_HOME=/var/lib/kenu

# Install essential runtime libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    libgomp1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root system user for sovereign node isolation & security
RUN useradd -ms /bin/bash kenu && \
    mkdir -p /app /var/lib/kenu /etc/kenu && \
    chown -R kenu:kenu /app /var/lib/kenu /etc/kenu

WORKDIR /app

# Copy built python packages and binary artifacts from builder stage
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages
COPY --from=builder /build /app

# Change ownership to non-root user
RUN chown -R kenu:kenu /app

USER kubu

# Expose ports for Node RPC, Web4 Bridge, and API Gateway
EXPOSE 8545 8080 9000

# Healthcheck configuration to monitor node synchronization and runtime readiness
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["python3", "cli/main.py"]
CMD ["--config", "/etc/kenu/config.json"]
