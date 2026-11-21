import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response

from api.config import get_settings
from api.logging_config import configure_logging
from api.repositories.postgres_repository import PostgresDB
from api.routers.journal_router import router as journal_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    configure_logging()
    settings = get_settings()
    async with PostgresDB(settings.database_url) as database:
        app.state.database = database
        try:
            logger.info("API is ready to receive requests")
            yield
        finally:
            logger.info("API is shutting down")
            del app.state.database


app = FastAPI(
    title="Journal API",
    description="A simple journal API for tracking daily work, struggles, and intentions",
    lifespan=lifespan,
)


@app.middleware("http")
async def add_security_headers(request: Request, call_next: object) -> Response:
    """Add HSTS and other security headers to every response."""
    response: Response = await call_next(request)  # type: ignore[operator]
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    return response


app.include_router(journal_router)
