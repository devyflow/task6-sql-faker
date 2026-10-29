CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS locales (
  code text PRIMARY KEY,
  label text NOT NULL,
  country_code text NOT NULL,
  phone_prefix text NOT NULL,
  center_lat double precision NOT NULL,
  center_lon double precision NOT NULL,
  radius_km double precision NOT NULL,
  height_mean double precision NOT NULL,
  height_sd double precision NOT NULL,
  weight_mean double precision NOT NULL,
  weight_sd double precision NOT NULL
);

CREATE TABLE IF NOT EXISTS first_names (
  locale text NOT NULL REFERENCES locales(code),
  value text NOT NULL,
  gender char(1) NOT NULL CHECK (gender IN ('F','M','X')),
  PRIMARY KEY(locale, value, gender)
);

CREATE TABLE IF NOT EXISTS last_names (
  locale text NOT NULL REFERENCES locales(code),
  value text NOT NULL,
  PRIMARY KEY(locale, value)
);

CREATE TABLE IF NOT EXISTS street_names (
  locale text NOT NULL REFERENCES locales(code),
  value text NOT NULL,
  PRIMARY KEY(locale, value)
);

CREATE TABLE IF NOT EXISTS cities (
  locale text NOT NULL REFERENCES locales(code),
  value text NOT NULL,
  region text NOT NULL,
  postal_prefix text NOT NULL,
  PRIMARY KEY(locale, value)
);

CREATE TABLE IF NOT EXISTS email_domains (
  locale text NOT NULL REFERENCES locales(code),
  value text NOT NULL,
  weight integer NOT NULL DEFAULT 1 CHECK (weight > 0),
  PRIMARY KEY(locale, value)
);

CREATE TABLE IF NOT EXISTS generation_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  locale text NOT NULL REFERENCES locales(code),
  seed bigint NOT NULL,
  batch_index integer NOT NULL DEFAULT 0 CHECK (batch_index >= 0),
  requested_rows integer NOT NULL CHECK (requested_rows BETWEEN 1 AND 1000000),
  created_at timestamptz NOT NULL DEFAULT now(),
  elapsed_ms numeric(14,3),
  rows_per_second numeric(14,2)
);

CREATE TABLE IF NOT EXISTS generated_people (
  batch_id uuid NOT NULL REFERENCES generation_batches(id) ON DELETE CASCADE,
  row_number integer NOT NULL,
  full_name text NOT NULL,
  title text,
  middle_name text,
  gender char(1) NOT NULL,
  eye_color text NOT NULL,
  age smallint NOT NULL,
  height_cm numeric(6,2) NOT NULL,
  weight_kg numeric(6,2) NOT NULL,
  address text NOT NULL,
  city text NOT NULL,
  region text NOT NULL,
  postal_code text NOT NULL,
  latitude numeric(10,7) NOT NULL,
  longitude numeric(10,7) NOT NULL,
  phone text NOT NULL,
  email text NOT NULL,
  PRIMARY KEY(batch_id, row_number)
);
ALTER TABLE generation_batches ADD COLUMN IF NOT EXISTS batch_index integer NOT NULL DEFAULT 0;
ALTER TABLE generated_people ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE generated_people ADD COLUMN IF NOT EXISTS middle_name text;
ALTER TABLE generated_people ADD COLUMN IF NOT EXISTS eye_color text NOT NULL DEFAULT 'brown';
CREATE INDEX IF NOT EXISTS generated_people_email_idx ON generated_people(email);
CREATE INDEX IF NOT EXISTS generated_people_batch_city_idx ON generated_people(batch_id, city);

INSERT INTO locales VALUES
('en_US','English - United States','US','+1',39.8283,-98.5795,2100,175,9.5,79,16),
('en_GB','English - United Kingdom','GB','+44',54.7024,-3.2766,650,173,9.2,76,15),
('de_DE','German - Germany','DE','+49',51.1657,10.4515,620,174,9.3,78,15),
('fr_FR','French - France','FR','+33',46.2276,2.2137,700,172,9.0,74,14),
('es_ES','Spanish - Spain','ES','+34',40.4637,-3.7492,700,171,8.8,73,14)
ON CONFLICT (code) DO NOTHING;

INSERT INTO first_names(locale,value,gender)
SELECT l.code, n.value, n.gender
FROM locales l
CROSS JOIN LATERAL (VALUES
 ('Alex','X'),('Avery','X'),('Jordan','X'),('Morgan','X'),('Taylor','X'),
 ('Olivia','F'),('Emma','F'),('Sophia','F'),('Amelia','F'),('Mia','F'),
 ('Liam','M'),('Noah','M'),('Oliver','M'),('Elijah','M'),('Lucas','M'),
 ('Charlotte','F'),('Evelyn','F'),('Harper','F'),('Eleanor','F'),('Camila','F'),
 ('James','M'),('Mateo','M'),('Henry','M'),('Theodore','M'),('William','M')
) AS n(value,gender)
ON CONFLICT DO NOTHING;

INSERT INTO last_names(locale,value)
SELECT l.code, n.value FROM locales l CROSS JOIN (VALUES
 ('Anderson'),('Bennett'),('Carter'),('Diaz'),('Edwards'),('Fischer'),('Garcia'),('Hughes'),
 ('Ivanov'),('Johnson'),('Klein'),('Laurent'),('Martin'),('Nguyen'),('Ortiz'),('Patel'),
 ('Quinn'),('Rivera'),('Schmidt'),('Turner'),('Usman'),('Valdez'),('Wilson'),('Xu'),('Young'),('Zimmerman')
) AS n(value) ON CONFLICT DO NOTHING;

INSERT INTO street_names(locale,value)
SELECT l.code, n.value FROM locales l CROSS JOIN (VALUES
 ('Oak Street'),('Maple Avenue'),('Cedar Lane'),('Station Road'),('River Way'),('Park Boulevard'),
 ('Market Street'),('Church Lane'),('Hill Road'),('Lake View'),('Garden Avenue'),('King Street'),
 ('Queen Road'),('Sunset Drive'),('Meadow Lane'),('High Street'),('Forest Way'),('Bridge Road'),
 ('Mill Street'),('Orchard Avenue')
) AS n(value) ON CONFLICT DO NOTHING;

INSERT INTO cities(locale,value,region,postal_prefix) VALUES
('en_US','New York','NY','100'),('en_US','Chicago','IL','606'),('en_US','Austin','TX','733'),('en_US','Seattle','WA','981'),('en_US','Denver','CO','802'),
('en_GB','London','England','SW1'),('en_GB','Manchester','England','M1'),('en_GB','Edinburgh','Scotland','EH1'),('en_GB','Cardiff','Wales','CF1'),('en_GB','Belfast','Northern Ireland','BT1'),
('de_DE','Berlin','Berlin','101'),('de_DE','Munich','Bavaria','803'),('de_DE','Hamburg','Hamburg','200'),('de_DE','Cologne','NRW','506'),('de_DE','Frankfurt','Hesse','603'),
('fr_FR','Paris','Ile-de-France','750'),('fr_FR','Lyon','Auvergne-Rhone-Alpes','690'),('fr_FR','Marseille','Provence','130'),('fr_FR','Toulouse','Occitanie','310'),('fr_FR','Lille','Hauts-de-France','590'),
('es_ES','Madrid','Community of Madrid','280'),('es_ES','Barcelona','Catalonia','080'),('es_ES','Valencia','Valencian Community','460'),('es_ES','Seville','Andalusia','410'),('es_ES','Bilbao','Basque Country','480')
ON CONFLICT DO NOTHING;

INSERT INTO email_domains(locale,value,weight)
SELECT l.code, d.value, d.weight FROM locales l CROSS JOIN (VALUES
 ('example.com',4),('mailbox.test',2),('northstar.example',1),('weyland.test',1)
) AS d(value,weight) ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION hash_uniform(p_seed bigint, p_row bigint, p_salt text)
RETURNS double precision LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT (('x' || substr(md5(p_seed::text || ':' || p_row::text || ':' || p_salt), 1, 15))::bit(60)::bigint + 1)::double precision
         / 1152921504606846977.0;
$$;

CREATE OR REPLACE FUNCTION hash_normal(p_seed bigint, p_row bigint, p_salt text)
RETURNS double precision LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT sqrt(-2.0 * ln(greatest(hash_uniform(p_seed,p_row,p_salt || ':u1'), 1e-12)))
       * cos(2.0 * pi() * hash_uniform(p_seed,p_row,p_salt || ':u2'));
$$;

CREATE OR REPLACE FUNCTION slug_email(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT trim(both '.' from regexp_replace(lower(unaccent_safe), '[^a-z0-9]+', '.', 'g'))
  FROM (SELECT translate(p_value,
    'áàäâãåçéèëêíìïîñóòöôõúùüûýÿžšß',
    'aaaaaaceeeeiiiinooooouuuuyyzss') AS unaccent_safe) s;
$$;

DROP PROCEDURE IF EXISTS generate_people_batch(text,bigint,integer,uuid);
CREATE OR REPLACE PROCEDURE generate_people_batch(
  IN p_locale text,
  IN p_seed bigint,
  IN p_rows integer,
  IN p_batch_index integer DEFAULT NULL,
  INOUT p_batch_id uuid DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
  v_started timestamptz := clock_timestamp();
  v_locale locales%ROWTYPE;
  v_batch_index integer;
BEGIN
  IF p_rows < 1 OR p_rows > 1000000 THEN
    RAISE EXCEPTION 'rows must be between 1 and 1000000';
  END IF;
  SELECT * INTO STRICT v_locale FROM locales WHERE code = p_locale;
  v_batch_index := COALESCE(
    p_batch_index,
    (SELECT COALESCE(max(batch_index),-1)+1 FROM generation_batches WHERE locale=p_locale AND seed=p_seed)
  );
  IF v_batch_index < 0 THEN RAISE EXCEPTION 'batch_index must be non-negative'; END IF;
  p_batch_id := COALESCE(p_batch_id, gen_random_uuid());
  INSERT INTO generation_batches(id,locale,seed,batch_index,requested_rows)
  VALUES(p_batch_id,p_locale,p_seed,v_batch_index,p_rows);

  INSERT INTO generated_people(
    batch_id,row_number,full_name,title,middle_name,gender,eye_color,age,height_cm,weight_kg,address,city,region,
    postal_code,latitude,longitude,phone,email
  )
  WITH rows AS (
    SELECT g AS n, v_batch_index::bigint*1000000 + g AS k,
      CASE WHEN hash_uniform(p_seed,v_batch_index::bigint*1000000+g,'gender') < .48 THEN 'F' WHEN hash_uniform(p_seed,v_batch_index::bigint*1000000+g,'gender') < .96 THEN 'M' ELSE 'X' END::char(1) AS gender,
      hash_uniform(p_seed,v_batch_index::bigint*1000000+g,'city') AS city_u
    FROM generate_series(1,p_rows) g
  ), picked AS (
    SELECT r.*,
      (SELECT value FROM first_names f WHERE f.locale=p_locale AND (f.gender=r.gender OR f.gender='X') ORDER BY value OFFSET floor(hash_uniform(p_seed,r.k,'first') * (SELECT count(*) FROM first_names x WHERE x.locale=p_locale AND (x.gender=r.gender OR x.gender='X'))) LIMIT 1) AS first_name,
      CASE WHEN hash_uniform(p_seed,r.k,'middle_use') < .45 THEN (SELECT value FROM first_names f WHERE f.locale=p_locale ORDER BY value OFFSET floor(hash_uniform(p_seed,r.k,'middle') * (SELECT count(*) FROM first_names x WHERE x.locale=p_locale)) LIMIT 1) END AS middle_name,
      (SELECT value FROM last_names f WHERE f.locale=p_locale ORDER BY value OFFSET floor(hash_uniform(p_seed,r.k,'last') * (SELECT count(*) FROM last_names x WHERE x.locale=p_locale)) LIMIT 1) AS last_name,
      (SELECT value FROM street_names f WHERE f.locale=p_locale ORDER BY value OFFSET floor(hash_uniform(p_seed,r.k,'street') * (SELECT count(*) FROM street_names x WHERE x.locale=p_locale)) LIMIT 1) AS street,
      (SELECT value FROM cities f WHERE f.locale=p_locale ORDER BY value OFFSET floor(r.city_u * (SELECT count(*) FROM cities x WHERE x.locale=p_locale)) LIMIT 1) AS city_name,
      (SELECT region FROM cities f WHERE f.locale=p_locale ORDER BY value OFFSET floor(r.city_u * (SELECT count(*) FROM cities x WHERE x.locale=p_locale)) LIMIT 1) AS region_name,
      (SELECT postal_prefix FROM cities f WHERE f.locale=p_locale ORDER BY value OFFSET floor(r.city_u * (SELECT count(*) FROM cities x WHERE x.locale=p_locale)) LIMIT 1) AS postal_prefix,
      hash_normal(p_seed,r.k,'height') AS z_height,
      hash_normal(p_seed,r.k,'weight') AS z_weight
    FROM rows r
  ), shaped AS (
    SELECT p.*,
      round((v_locale.height_mean + v_locale.height_sd * p.z_height)::numeric,2) AS height_value,
      18 + floor(power(hash_uniform(p_seed,p.k,'age'),0.68)*65)::integer AS age_value,
      (hash_uniform(p_seed,p.k,'geo_distance') * v_locale.radius_km / 6371.0088) AS angular_distance,
      (2*pi()*hash_uniform(p_seed,p.k,'geo_bearing')) AS bearing
    FROM picked p
  ), final AS (
    SELECT s.*,
      round(greatest(40, v_locale.weight_mean + .42*(s.height_value-v_locale.height_mean) + v_locale.weight_sd*s.z_weight)::numeric,2) AS weight_value,
      asin(sin(radians(v_locale.center_lat))*cos(s.angular_distance) + cos(radians(v_locale.center_lat))*sin(s.angular_distance)*cos(s.bearing)) AS lat_rad,
      radians(v_locale.center_lon) + atan2(sin(s.bearing)*sin(s.angular_distance)*cos(radians(v_locale.center_lat)), cos(s.angular_distance)-sin(radians(v_locale.center_lat))*sin(asin(sin(radians(v_locale.center_lat))*cos(s.angular_distance) + cos(radians(v_locale.center_lat))*sin(s.angular_distance)*cos(s.bearing)))) AS lon_rad
    FROM shaped s
  )
  SELECT p_batch_id,n,
    concat_ws(' ', CASE WHEN hash_uniform(p_seed,k,'title_use') < .35 THEN CASE gender WHEN 'F' THEN 'Ms.' WHEN 'M' THEN 'Mr.' ELSE 'Mx.' END END, first_name, middle_name, last_name),
    CASE WHEN hash_uniform(p_seed,k,'title_use') < .35 THEN CASE gender WHEN 'F' THEN 'Ms.' WHEN 'M' THEN 'Mr.' ELSE 'Mx.' END END,
    middle_name,gender,
    (ARRAY['brown','blue','green','hazel','gray'])[1+floor(hash_uniform(p_seed,k,'eye')*5)::int],
    age_value,height_value,weight_value,
    CASE WHEN p_locale IN ('de_DE','fr_FR','es_ES') THEN street || ' ' || (1+floor(hash_uniform(p_seed,k,'house')*9999))::int ELSE (1+floor(hash_uniform(p_seed,k,'house')*9999))::int || ' ' || street END,
    city_name,region_name,postal_prefix || lpad(floor(hash_uniform(p_seed,k,'postal')*1000)::int::text,3,'0'),
    round(degrees(lat_rad)::numeric,7),round((((degrees(lon_rad)+540)::numeric % 360)-180),7),
    CASE WHEN hash_uniform(p_seed,k,'phone_format') < .5
      THEN v_locale.phone_prefix || ' ' || lpad(floor(hash_uniform(p_seed,k,'phone_a')*1000)::int::text,3,'0') || ' ' || lpad(floor(hash_uniform(p_seed,k,'phone_b')*10000000)::int::text,7,'0')
      ELSE v_locale.phone_prefix || ' (' || lpad(floor(hash_uniform(p_seed,k,'phone_a')*1000)::int::text,3,'0') || ') ' || lpad(floor(hash_uniform(p_seed,k,'phone_b')*10000000)::int::text,7,'0') END,
    slug_email(first_name || '.' || last_name) || '.' || v_batch_index || '.' || n || '@' || (SELECT value FROM email_domains d WHERE d.locale=p_locale ORDER BY value OFFSET floor(hash_uniform(p_seed,k,'domain')*(SELECT count(*) FROM email_domains x WHERE x.locale=p_locale)) LIMIT 1)
  FROM final;

  UPDATE generation_batches
  SET elapsed_ms = extract(epoch FROM clock_timestamp()-v_started)*1000,
      rows_per_second = p_rows / greatest(extract(epoch FROM clock_timestamp()-v_started),0.000001)
  WHERE id=p_batch_id;
END;
$$;

CREATE OR REPLACE VIEW batch_summary AS
SELECT b.id,b.locale,b.seed,b.batch_index,b.requested_rows,b.created_at,b.elapsed_ms,b.rows_per_second,
       count(p.*) AS stored_rows,round(avg(p.height_cm),2) AS avg_height_cm,round(avg(p.weight_kg),2) AS avg_weight_kg
FROM generation_batches b LEFT JOIN generated_people p ON p.batch_id=b.id
GROUP BY b.id;
