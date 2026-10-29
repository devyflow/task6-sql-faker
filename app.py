from __future__ import annotations

import csv
import io
import os
from pathlib import Path
from typing import Optional
from uuid import UUID

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parent
SCHEMA_PATH = ROOT / "schema.sql"
load_dotenv(ROOT / ".env.local")
load_dotenv(ROOT / ".env")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/sql_faker")
pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=8, kwargs={"row_factory": dict_row}, open=False)

app = FastAPI(title="SQL Faker Lab", version="1.0.0")
app.mount("/static", StaticFiles(directory=ROOT / "static"), name="static")


class GenerateRequest(BaseModel):
    locale: str = Field(pattern=r"^[a-z]{2}_[A-Z]{2}$")
    seed: int = Field(ge=0, le=9_223_372_036_854_775_807)
    rows: int = Field(ge=1, le=1_000_000)
    batch_index: Optional[int] = Field(default=None, ge=0)


@app.on_event("startup")
def startup() -> None:
    pool.open(wait=True)
    # Keep managed deployments self-initializing. The schema is idempotent and
    # is also mounted into the PostgreSQL container for local docker-compose.
    with pool.connection() as connection:
        connection.execute(SCHEMA_PATH.read_text(encoding="utf-8"), prepare=False)


@app.on_event("shutdown")
def shutdown() -> None:
    pool.close()


@app.get("/")
def index():
    return FileResponse(ROOT / "static" / "index.html")


@app.get("/health")
def health():
    try:
        with pool.connection() as connection:
            result = connection.execute("SELECT current_database() AS database, version() AS version").fetchone()
        return {"status": "ok", **result}
    except Exception as exc:
        raise HTTPException(503, f"Database unavailable: {exc}") from exc


@app.get("/api/locales")
def locales():
    with pool.connection() as connection:
        return connection.execute(
            "SELECT code,label,country_code,radius_km FROM locales ORDER BY label"
        ).fetchall()


@app.post("/api/generate", status_code=201)
def generate(request: GenerateRequest):
    try:
        with pool.connection() as connection:
            row = connection.execute(
                "CALL generate_people_batch(%s,%s,%s,%s,NULL)",
                (request.locale, request.seed, request.rows, request.batch_index),
            ).fetchone()
            batch_id = row["p_batch_id"]
            summary = connection.execute(
                "SELECT * FROM batch_summary WHERE id=%s", (batch_id,)
            ).fetchone()
            preview = connection.execute(
                "SELECT * FROM generated_people WHERE batch_id=%s ORDER BY row_number LIMIT 20",
                (batch_id,),
            ).fetchall()
        return {"summary": summary, "preview": preview}
    except Exception as exc:
        raise HTTPException(400, str(exc)) from exc


@app.get("/api/batches")
def batches(limit: int = Query(default=25, ge=1, le=100)):
    with pool.connection() as connection:
        return connection.execute(
            "SELECT * FROM batch_summary ORDER BY created_at DESC LIMIT %s", (limit,)
        ).fetchall()


@app.get("/api/batches/{batch_id}")
def batch(batch_id: UUID, limit: int = Query(default=100, ge=1, le=1000)):
    with pool.connection() as connection:
        summary = connection.execute(
            "SELECT * FROM batch_summary WHERE id=%s", (batch_id,)
        ).fetchone()
        if not summary:
            raise HTTPException(404, "Batch not found")
        rows = connection.execute(
            "SELECT * FROM generated_people WHERE batch_id=%s ORDER BY row_number LIMIT %s",
            (batch_id, limit),
        ).fetchall()
    return {"summary": summary, "rows": rows}


@app.get("/api/batches/{batch_id}/export.csv")
def export_csv(batch_id: UUID):
    def stream():
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        columns = [
            "row_number", "full_name", "title", "middle_name", "gender", "eye_color", "age", "height_cm", "weight_kg",
            "address", "city", "region", "postal_code", "latitude", "longitude", "phone", "email",
        ]
        writer.writerow(columns)
        yield buffer.getvalue()
        buffer.seek(0); buffer.truncate(0)
        with pool.connection() as connection:
            with connection.cursor(name=f"export_{str(batch_id).replace('-', '')}") as cursor:
                cursor.execute(
                    f"SELECT {','.join(columns)} FROM generated_people WHERE batch_id=%s ORDER BY row_number",
                    (batch_id,),
                )
                for row in cursor:
                    writer.writerow(row)
                    yield buffer.getvalue()
                    buffer.seek(0); buffer.truncate(0)

    return StreamingResponse(
        stream(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="people-{batch_id}.csv"'},
    )
