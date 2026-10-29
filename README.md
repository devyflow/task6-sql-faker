# SQL Faker Lab — Task 6

Locale-aware, deterministic synthetic-person generation in PostgreSQL. Python does not generate, randomize, format or enrich any person record; the web app validates three inputs and calls one stored procedure.

## Requirement coverage

- `generate_people_batch(locale, seed, rows, batch_id)` is the only generation entry point.
- Deterministic `hash_uniform` and Box-Muller `hash_normal` functions derive independent values from `(seed, row_number, salt)`.
- Locale lookup tables supply first names, last names, street names, cities, regions, postal prefixes, domains and phone prefixes.
- Names, gender, discrete age, normally distributed/correlated height and weight, addresses, spherical coordinates, phones and collision-resistant e-mails are generated in SQL.
- Latitude/longitude uses destination-point spherical geometry around each locale's center and radius—not a rectangular latitude/longitude box.
- Batch timing and rows/second are recorded inside the same procedure.
- Up to 1,000,000 rows per batch; the UI fetches a bounded preview and streams full CSV exports with a server-side cursor.
- The same locale, seed and row number always produce the same record.

## Run

With Docker:

```bash
docker compose up --build
```

Open `http://localhost:8000`.

Without Docker, create a PostgreSQL 15+ database and run:

```bash
psql "$DATABASE_URL" -f schema.sql
python -m venv .venv
pip install -r requirements.txt
uvicorn app:app --reload
```

## Verify and benchmark

```bash
python -m unittest -v
python benchmark.py
```

`benchmark.py` measures median database-reported latency for 1k, 10k and 100k rows and creates two 1,000-row batches with the same seed. The bidirectional `EXCEPT` comparison must report `determinism_differences,0`.

## Request flow

```text
Browser: locale + seed + count
              |
              v
FastAPI validation and parameterized CALL
              |
              v
PostgreSQL generate_people_batch
  |-- deterministic hash streams
  |-- lookup selection
  |-- normal/discrete distributions
  |-- spherical geolocation
  |-- contact formatting
              |
              v
generated_people + batch metrics
              |
              v
bounded JSON preview / streamed CSV
```

## API

- `GET /health`
- `GET /api/locales`
- `POST /api/generate` with `{"locale":"en_US","seed":42,"rows":10000}`
- `GET /api/batches`
- `GET /api/batches/{id}`
- `GET /api/batches/{id}/export.csv`

## Deployment

Deploy the container and a managed PostgreSQL database. Apply `schema.sql` once, set `DATABASE_URL`, and expose the app container. Keep the database private; only the FastAPI service should be public.
