FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim

# Build-time argument for git commit SHA
ARG GIT_SHA="unknown"
ENV GIT_SHA=$GIT_SHA

# Set environment variables for Python and uv
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PORT=8000

# Create a non-root user and group
RUN groupadd -r journal && useradd -r -g journal -d /app journal

WORKDIR /app

# Copy dependency definition files
COPY pyproject.toml uv.lock ./

# Install production dependencies (excluding dev group)
RUN uv sync --frozen --no-dev

# Copy application source code and schema migration
COPY api/ ./api/
COPY database_setup.sql ./

# Place virtual environment in PATH
ENV PATH="/app/.venv/bin:$PATH"

# Set permissions for non-root user
RUN chown -R journal:journal /app

USER journal

EXPOSE 8000

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
