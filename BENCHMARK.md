# Verified PostgreSQL 17 benchmark

Run on 2026-10-29 against PostgreSQL 17.11 for Windows, using an isolated local
cluster and the committed `schema.sql`.

| Rows | Database-reported elapsed time | Throughput |
| ---: | ---: | ---: |
| 1,000 | 890.995 ms | 1,119.84 rows/s |
| 10,000 | 10,718.375 ms | 932.98 rows/s |
| 100,000 | 120,691.663 ms | 828.56 rows/s |

The benchmark's bidirectional `EXCEPT` comparison of two independently generated
1,000-row batches with the same locale and seed returned:

```text
determinism_differences,0
```

Validation command:

```powershell
$env:DATABASE_URL='postgresql://postgres@localhost:55432/task6'
python benchmark.py
```
