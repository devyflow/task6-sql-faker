from __future__ import annotations

import os
from statistics import median

import psycopg
from dotenv import load_dotenv
from psycopg.rows import dict_row

load_dotenv(".env.local")
load_dotenv(".env")
dsn = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/sql_faker")

with psycopg.connect(dsn, row_factory=dict_row) as connection:
    print("rows,elapsed_ms,rows_per_second")
    for size in (1_000, 10_000, 100_000):
        samples = []
        for run in range(3):
            batch = connection.execute(
                "CALL generate_people_batch(%s,%s,%s,%s,NULL)",
                ("en_US", 20261029 + run, size, 0),
            ).fetchone()["p_batch_id"]
            result = connection.execute(
                "SELECT elapsed_ms,rows_per_second FROM generation_batches WHERE id=%s", (batch,)
            ).fetchone()
            samples.append(result)
        print(f"{size},{median(float(x['elapsed_ms']) for x in samples):.3f},{median(float(x['rows_per_second']) for x in samples):.2f}")

    first = connection.execute(
        "CALL generate_people_batch(%s,%s,%s,%s,NULL)", ("en_US", 424242, 1000, 7)
    ).fetchone()["p_batch_id"]
    second = connection.execute(
        "CALL generate_people_batch(%s,%s,%s,%s,NULL)", ("en_US", 424242, 1000, 7)
    ).fetchone()["p_batch_id"]
    difference = connection.execute(
        """
        SELECT count(*) AS differences FROM (
          (SELECT row_number,full_name,title,middle_name,gender,eye_color,age,height_cm,weight_kg,address,city,region,postal_code,latitude,longitude,phone,email
           FROM generated_people WHERE batch_id=%s
           EXCEPT
           SELECT row_number,full_name,title,middle_name,gender,eye_color,age,height_cm,weight_kg,address,city,region,postal_code,latitude,longitude,phone,email
           FROM generated_people WHERE batch_id=%s)
          UNION ALL
          (SELECT row_number,full_name,title,middle_name,gender,eye_color,age,height_cm,weight_kg,address,city,region,postal_code,latitude,longitude,phone,email
           FROM generated_people WHERE batch_id=%s
           EXCEPT
           SELECT row_number,full_name,title,middle_name,gender,eye_color,age,height_cm,weight_kg,address,city,region,postal_code,latitude,longitude,phone,email
           FROM generated_people WHERE batch_id=%s)
        ) d
        """,
        (first, second, second, first),
    ).fetchone()["differences"]
    print(f"determinism_differences,{difference}")
