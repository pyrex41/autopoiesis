# Dockerfile for Autopoiesis
#
# Autopoiesis is a self-configuring, self-extending agent platform
# built on Common Lisp's homoiconic foundation.
#
# Build: docker build -t autopoiesis .
# Run:   docker run -v autopoiesis-data:/data -p 8080:8080 autopoiesis

FROM clfoundation/sbcl:latest

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # For SSL/TLS (dexador HTTP client)
    libssl-dev \
    ca-certificates \
    # For ncurses terminal UI (cl-charms)
    libncurses-dev \
    # For cryptographic hashing (ironclad)
    libffi-dev \
    # For Woo async HTTP server (libev backend)
    libev-dev \
    # For LMDB persistent substrate backend
    liblmdb-dev \
    # Build tools and utilities
    build-essential \
    curl \
    git \
    # For HTTP healthchecks in docker-compose
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install rho-cli (Jarvis LLM provider)
ARG TARGETARCH
ARG RHO_VERSION=v0.4.0
RUN ARCH=$(case "$TARGETARCH" in arm64) echo "arm64" ;; *) echo "x64" ;; esac) && \
    curl -fsSL "https://github.com/pyrex41/rho/releases/download/${RHO_VERSION}/rho-cli-linux-${ARCH}" \
      -o /usr/local/bin/rho-cli && \
    chmod +x /usr/local/bin/rho-cli

# Setup Quicklisp
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp \
    && echo | sbcl --noinform --non-interactive \
            --load quicklisp.lisp \
            --eval "(quicklisp-quickstart:install)" \
            --eval "(ql:add-to-init-file)" \
            --quit \
    && rm quicklisp.lisp

# Create application directory
WORKDIR /app

# Copy system definitions first (for better layer caching)
COPY autopoiesis.asd substrate.asd ./

# Pre-load dependencies in batches to stay within SBCL default heap
RUN sbcl --noinform --non-interactive \
    --eval "(push #P\"/app/\" asdf:*central-registry*)" \
    --eval "(ql:quickload '(:alexandria :bordeaux-threads :cl-json :local-time :cl-ppcre :log4cl :ironclad :flexi-streams :babel :fset) :silent t)" \
    --eval "(quit)"

RUN sbcl --noinform --non-interactive \
    --eval "(push #P\"/app/\" asdf:*central-registry*)" \
    --eval "(ql:quickload '(:dexador :cl-charms :hunchentoot :fiveam :lparallel) :silent t)" \
    --eval "(quit)"

RUN sbcl --noinform --non-interactive \
    --eval "(push #P\"/app/\" asdf:*central-registry*)" \
    --eval "(ql:quickload '(:clack :lack :websocket-driver :com.inuoe.jzon :cl-messagepack :lmdb) :silent t)" \
    --eval "(quit)"

# Copy source code and vendored dependencies
COPY src/ src/
COPY scripts/ scripts/
COPY test/ test/
COPY vendor/ vendor/

# Load and compile the full system (core + API)
RUN sbcl --noinform --non-interactive \
    --eval "(push #P\"/app/\" asdf:*central-registry*)" \
    --eval "(push #P\"/app/vendor/woo/\" asdf:*central-registry*)" \
    --eval "(handler-case \
              (progn \
                (ql:quickload :autopoiesis/api :silent t) \
                (format t \"~%System loaded successfully.~%\") \
                (quit :unix-status 0)) \
              (error (e) \
                (format t \"~%Load FAILED: ~a~%\" e) \
                (quit :unix-status 1)))"

# Runtime configuration via environment variables
ENV AUTOPOIESIS_DATA_DIR=/data
ENV AUTOPOIESIS_LOG_DIR=/data/logs
ENV AUTOPOIESIS_LOG_LEVEL=info
ENV AUTOPOIESIS_HOST=0.0.0.0
ENV AUTOPOIESIS_PORT=8080

# Create data and static directories
RUN mkdir -p /data/logs /data/snapshots /app/static

# Volume for persistent data (snapshots, logs, config)
VOLUME /data

# Expose HTTP ports (main app and monitoring)
EXPOSE 8080 8081

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD sbcl --noinform --non-interactive \
        --eval "(push #P\"/app/\" asdf:*central-registry*)" \
        --eval "(ql:quickload :autopoiesis :silent t)" \
        --eval "(if (autopoiesis:health-check-ok-p) (quit :unix-status 0) (quit :unix-status 1))" \
        || exit 1

# Default command: start the REPL with system loaded
# Override with specific entry point as needed
CMD ["sbcl", "--noinform", \
     "--eval", "(push #P\"/app/\" asdf:*central-registry*)", \
     "--eval", "(ql:quickload :autopoiesis :silent t)", \
     "--eval", "(in-package :autopoiesis)", \
     "--eval", "(format t \"~%Autopoiesis loaded. Type (help) for commands.~%\")"]
