# SQL Faker stored-procedure API

All synthetic fields are produced by PostgreSQL. The Python service validates
inputs, calls the procedure, and reads rows; it contains no Faker or random-data
logic.

## `generate_people_batch`

```sql
CALL generate_people_batch(locale, seed, rows, batch_index, NULL);
```

Arguments:

- `locale text`: a key from `locales`, such as `en_US` or `de_DE`.
- `seed bigint`: the reproducibility seed.
- `rows integer`: 1 through 1,000,000.
- `batch_index integer`: zero-based position in the stream. Pass `NULL` to use
  the next index already recorded for the locale/seed pair.
- final `NULL`: PostgreSQL fills the `INOUT p_batch_id` UUID and returns it.

Every random stream is keyed by `(seed, batch_index, row_number, salt)`. The
same four values therefore reproduce the same person even in a different
database. Different salts independently select gender, names, format variants,
physical values, address components, coordinates, phone, and e-mail.

The procedure records elapsed milliseconds and rows/second in
`generation_batches`. Generated rows are stored in `generated_people` and can
be joined through the returned UUID.

## Random primitives

### `hash_uniform(seed, row, salt)`

Hashes the key with MD5, converts 60 bits to an integer, and scales the result
to the open interval `(0, 1)`. It is immutable, deterministic, and does not use
session-global `random()` state.

### `hash_normal(seed, row, salt)`

Uses two independent `hash_uniform` streams and the Box-Muller transform:

```text
z = sqrt(-2 ln(u1)) cos(2 pi u2)
```

The procedure scales these standard-normal values with locale-specific means
and standard deviations. Weight is correlated with height while retaining an
independent normal component. Age and eye color are discrete distributions.

### `slug_email(value)`

Transliterates common accented Latin characters, lowercases the input, and
replaces non-alphanumeric runs with dots for deterministic e-mail local parts.

## Locale and formatting rules

Lookup tables use a `locale` column rather than one table per language. Name,
street, city, postal, domain, phone-prefix, geographic, and physical-distribution
data can be extended by inserting rows for another locale.

Full names deterministically vary between titled/untitled and
middle-name/no-middle-name forms. Addresses switch between house-first and
street-first conventions, while phone numbers use two formatting patterns.

## Spherical geolocation

For each row the procedure chooses a bearing uniformly in `[0, 2π)` and a
distance from the locale center, then applies the great-circle destination
formula. Longitude is normalized to `[-180, 180)`. This avoids the rectangular
latitude/longitude sampling error and keeps points on the sphere around the
selected locale.

## Examples

Generate the first 10 German rows:

```sql
CALL generate_people_batch('de_DE', 42, 10, 0, NULL);
```

Generate the next stored batch for the same stream:

```sql
CALL generate_people_batch('de_DE', 42, 10, NULL, NULL);
```

Inspect the latest batch:

```sql
SELECT * FROM batch_summary ORDER BY created_at DESC LIMIT 1;
SELECT * FROM generated_people WHERE batch_id = '<returned UUID>' ORDER BY row_number;
```
