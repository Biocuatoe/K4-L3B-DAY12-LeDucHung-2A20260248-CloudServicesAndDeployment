# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization
#
# Multi-stage production-ready Dockerfile:
#   - Stage 1 (builder): creates venv with dependencies
#   - Stage 2 (runtime): slim Python image, non-root user, healthcheck
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: Build dependencies ──────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Copy requirements.txt first (layer caching: only rebuilds deps if requirements.txt changes)
COPY requirements.txt .

# Install dependencies in a virtual environment (preserves console scripts)
RUN python -m venv /app/venv && \
    /app/venv/bin/pip install --no-cache-dir -r requirements.txt

# ── Stage 2: Runtime ──────────────────────────────────────────────
FROM python:3.11-slim

# Create a non-root user for security
RUN groupadd --gid 1000 appgroup && \
    useradd --uid 1000 --gid appgroup --shell /bin/bash --create-home appuser

WORKDIR /app

# Copy virtual environment from builder stage
COPY --from=builder /app/venv /app/venv

# Set PATH to include the venv and PYTHONPATH
ENV PATH="/app/venv/bin:$PATH"
ENV PYTHONPATH=/app

# Set default PORT if not provided
ENV PORT=8000

# Copy application source
COPY app/ ./app/
COPY utils/ ./utils/

# Switch to non-root user
USER appuser

# Expose port from environment variable (cloud platforms set PORT dynamically)
EXPOSE ${PORT}

# Healthcheck: Docker pings /health to determine container health
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT}/health')" || exit 1

# Run uvicorn in production mode (no reload)
# Using shell form for proper environment variable expansion
CMD /app/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT
