# Verified PostgreSQL 17 benchmark

Run on 2026-10-29 against PostgreSQL 17.11 for Windows, using an isolated local
cluster and the committed `schema.sql`.

| Rows | Database-reported elapsed time | Throughput |
| ---: | ---: | ---: |
| 1,000 | 2,590.934 ms | 385.95 rows/s |
| 10,000 | 15,591.112 ms | 641.39 rows/s |
| 100,000 | 144,911.646 ms | 690.08 rows/s |

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
