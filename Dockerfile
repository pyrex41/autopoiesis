# Dockerfile for Autopoiesis
#
# Autopoiesis is a self-configuring, self-extending agent platform
# built on Common Lisp's homoiconic foundation.
#
# Build: docker build -t autopoiesis .
# Run:   docker run -v autopoiesis-data:/data -p 8080:8080 autopoiesis

FROM clfoundation/sbcl:2.4.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # For SSL/TLS (dexador HTTP client)
    libssl-dev \
    ca-certificates \
    # For ncurses terminal UI (cl-charms)
    libncurses-dev \
    # For cryptographic hashing (ironclad)
    libffi-dev \
    # Build tools
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Setup Quicklisp
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp \
    && sbcl --noinform --non-interactive \
            --load quicklisp.lisp \
            --eval "(quicklisp-quickstart:install)" \
            --eval "(ql:add-to-init-file)" \
            --quit \
    && rm quicklisp.lisp

# Create application directory
WORKDIR /app

# Copy system definition first (for better layer caching)
COPY autopoiesis.asd .

# Pre-load dependencies (cached layer)
RUN sbcl --noinform --non-interactive \
    --eval "(push #P\"/app/\" asdf:*central-registry*)" \
    --eval "(ql:quickload '(:alexandria :bordeaux-threads :cl-json :local-time :cl-ppcre :log4cl :ironclad :flexi-streams :babel :dexador :cl-charms :fiveam) :silent t)" \
    --eval "(quit)"

# Copy source code
COPY src/ src/
COPY scripts/ scripts/
COPY test/ test/

# Load and compile the system
RUN sbcl --noinform --non-interactive \
    --eval "(push #P\"/app/\" asdf:*central-registry*)" \
    --eval "(handler-case \
              (progn \
                (ql:quickload :autopoiesis :silent t) \
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

# Create data directories
RUN mkdir -p /data/logs /data/snapshots

# Volume for persistent data (snapshots, logs, config)
VOLUME /data

# Expose HTTP port
EXPOSE 8080

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
