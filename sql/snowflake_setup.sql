-- ============================================================
-- TTC Transit Delay Analytics -- Snowflake Setup
-- ============================================================
-- Run these in order. Replace <YOUR_SAS_TOKEN> with a real
-- Azure Blob Storage SAS token before running the STAGE section.
-- Never commit a real token to source control.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Database, schema, and file format
-- ------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS TTC_ANALYTICS;
CREATE SCHEMA IF NOT EXISTS TTC_ANALYTICS.RAW;
USE DATABASE TTC_ANALYTICS;
USE SCHEMA RAW;

SHOW WAREHOUSES;

CREATE OR REPLACE FILE FORMAT JSON_ARRAY_FORMAT
  TYPE = JSON
  STRIP_OUTER_ARRAY = TRUE;


-- ------------------------------------------------------------
-- 2. External stage -- connects Snowflake to Azure Blob Storage
-- ------------------------------------------------------------
CREATE OR REPLACE STAGE TTC_RAW_STAGE
  URL = 'azure://ttcanalyticsraw26.blob.core.windows.net/raw-ttc-data'
  CREDENTIALS = (AZURE_SAS_TOKEN = '<YOUR_SAS_TOKEN>')
  FILE_FORMAT = JSON_ARRAY_FORMAT;

-- Sanity checks -- confirm the stage can see and read real files
LIST @TTC_RAW_STAGE;
SELECT $1 FROM @TTC_RAW_STAGE/pull_date=2026-08-27/subway_delay_codes.json LIMIT 5;
SELECT $1 FROM @TTC_RAW_STAGE/pull_date=2026-08-27/subway_delays.json LIMIT 5;


-- ------------------------------------------------------------
-- 3. Raw layer -- one VARIANT table per dataset
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE RAW_SUBWAY_DELAYS (raw_data VARIANT);
CREATE OR REPLACE TABLE RAW_BUS_DELAYS (raw_data VARIANT);
CREATE OR REPLACE TABLE RAW_STREETCAR_DELAYS (raw_data VARIANT);

CREATE OR REPLACE TABLE RAW_SUBWAY_CODES (raw_data VARIANT);
CREATE OR REPLACE TABLE RAW_BUS_CODES (raw_data VARIANT);
CREATE OR REPLACE TABLE RAW_STREETCAR_CODES (raw_data VARIANT);

-- Example one-time load (the automated Task below handles this daily)
COPY INTO RAW_SUBWAY_DELAYS (raw_data)
  FROM @TTC_RAW_STAGE/pull_date=2026-08-27/subway_delays.json
  FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT);

COPY INTO RAW_BUS_DELAYS (raw_data)
  FROM @TTC_RAW_STAGE/pull_date=2026-08-27/bus_delays.json
  FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT);

COPY INTO RAW_STREETCAR_DELAYS (raw_data)
  FROM @TTC_RAW_STAGE/pull_date=2026-08-27/streetcar_delays.json
  FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT);

COPY INTO RAW_SUBWAY_CODES (raw_data)
  FROM @TTC_RAW_STAGE/pull_date=2026-08-27/subway_delay_codes.json
  FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT);

COPY INTO RAW_BUS_CODES (raw_data)
  FROM @TTC_RAW_STAGE/pull_date=2026-08-27/bus_delay_codes.json
  FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT);

COPY INTO RAW_STREETCAR_CODES (raw_data)
  FROM @TTC_RAW_STAGE/pull_date=2026-08-27/streetcar_delay_codes.json
  FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT);

-- Row count sanity check
SELECT 'subway' AS mode, COUNT(*) FROM RAW_SUBWAY_DELAYS
UNION ALL
SELECT 'bus', COUNT(*) FROM RAW_BUS_DELAYS
UNION ALL
SELECT 'streetcar', COUNT(*) FROM RAW_STREETCAR_DELAYS;


-- ------------------------------------------------------------
-- 4. Staging layer -- typed, cleaned views on top of raw JSON
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW STG_SUBWAY_DELAYS AS
SELECT
    raw_data:"_id"::INT                        AS delay_id,
    raw_data:"date_clean"::DATE                AS delay_date,
    raw_data:"Time"::TIME                      AS delay_time,
    raw_data:"Day"::STRING                     AS day_of_week,
    raw_data:"Station"::STRING                 AS station,
    raw_data:"Code"::STRING                    AS delay_code,
    raw_data:"Min Delay"::INT                  AS min_delay,
    raw_data:"Min Gap"::INT                    AS min_gap,
    raw_data:"Bound"::STRING                   AS bound,
    raw_data:"Line"::STRING                    AS line,
    raw_data:"Vehicle"::STRING                 AS vehicle,
    'subway'                                   AS mode
FROM RAW_SUBWAY_DELAYS;

CREATE OR REPLACE VIEW STG_BUS_DELAYS AS
SELECT
    raw_data:"_id"::INT                        AS delay_id,
    raw_data:"date_clean"::DATE                AS delay_date,
    raw_data:"Time"::TIME                      AS delay_time,
    raw_data:"Day"::STRING                     AS day_of_week,
    raw_data:"Station"::STRING                 AS station,
    raw_data:"Code"::STRING                    AS delay_code,
    raw_data:"Min Delay"::INT                  AS min_delay,
    raw_data:"Min Gap"::INT                    AS min_gap,
    raw_data:"Bound"::STRING                   AS bound,
    raw_data:"Line"::STRING                    AS line,
    raw_data:"Vehicle"::STRING                 AS vehicle,
    'bus'                                      AS mode
FROM RAW_BUS_DELAYS;

CREATE OR REPLACE VIEW STG_STREETCAR_DELAYS AS
SELECT
    raw_data:"_id"::INT                        AS delay_id,
    raw_data:"date_clean"::DATE                AS delay_date,
    raw_data:"Time"::TIME                      AS delay_time,
    raw_data:"Day"::STRING                     AS day_of_week,
    raw_data:"Station"::STRING                 AS station,
    raw_data:"Code"::STRING                    AS delay_code,
    raw_data:"Min Delay"::INT                  AS min_delay,
    raw_data:"Min Gap"::INT                    AS min_gap,
    raw_data:"Bound"::STRING                   AS bound,
    raw_data:"Line"::STRING                    AS line,
    raw_data:"Vehicle"::STRING                 AS vehicle,
    'streetcar'                                AS mode
FROM RAW_STREETCAR_DELAYS;

CREATE OR REPLACE VIEW STG_ALL_DELAYS AS
SELECT * FROM STG_SUBWAY_DELAYS
UNION ALL
SELECT * FROM STG_BUS_DELAYS
UNION ALL
SELECT * FROM STG_STREETCAR_DELAYS;

CREATE OR REPLACE VIEW STG_SUBWAY_CODES AS
SELECT
    raw_data:"CODE"::STRING         AS delay_code,
    raw_data:"DESCRIPTION"::STRING  AS code_description,
    'subway'                        AS mode
FROM RAW_SUBWAY_CODES;

CREATE OR REPLACE VIEW STG_BUS_CODES AS
SELECT
    raw_data:"CODE"::STRING         AS delay_code,
    raw_data:"DESCRIPTION"::STRING  AS code_description,
    'bus'                           AS mode
FROM RAW_BUS_CODES;

CREATE OR REPLACE VIEW STG_STREETCAR_CODES AS
SELECT
    raw_data:"CODE"::STRING         AS delay_code,
    raw_data:"DESCRIPTION"::STRING  AS code_description,
    'streetcar'                     AS mode
FROM RAW_STREETCAR_CODES;

CREATE OR REPLACE VIEW STG_ALL_CODES AS
SELECT * FROM STG_SUBWAY_CODES
UNION ALL
SELECT * FROM STG_BUS_CODES
UNION ALL
SELECT * FROM STG_STREETCAR_CODES;

-- Verify the join between delays and their code descriptions resolves cleanly
SELECT
    d.mode, d.station, d.delay_code, c.code_description, d.min_delay, d.delay_date
FROM STG_ALL_DELAYS d
LEFT JOIN STG_ALL_CODES c
    ON d.delay_code = c.delay_code
    AND d.mode = c.mode
LIMIT 10;


-- ------------------------------------------------------------
-- 5. Star schema -- dimension and fact tables
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_DELAY_CODE AS
SELECT
    ROW_NUMBER() OVER (ORDER BY mode, delay_code) AS code_key,
    delay_code,
    REPLACE(code_description, 'â', '-') AS code_description,
    mode
FROM STG_ALL_CODES;

CREATE OR REPLACE TABLE DIM_DATE AS
SELECT
    DATEADD(day, seq4(), '2025-01-01') AS full_date,
    YEAR(full_date) AS year,
    MONTH(full_date) AS month,
    MONTHNAME(full_date) AS month_name,
    QUARTER(full_date) AS quarter,
    DAYNAME(full_date) AS day_name,
    CASE WHEN DAYOFWEEK(full_date) IN (0,6) THEN TRUE ELSE FALSE END AS is_weekend
FROM TABLE(GENERATOR(ROWCOUNT => 900));

CREATE OR REPLACE TABLE FACT_DELAYS AS
SELECT
    d.delay_id, d.mode, d.delay_date, d.delay_time, d.station,
    d.line, d.bound, d.vehicle, d.min_delay, d.min_gap,
    c.code_key, c.code_description
FROM STG_ALL_DELAYS d
LEFT JOIN DIM_DELAY_CODE c
    ON d.delay_code = c.delay_code
    AND d.mode = c.mode;

-- Verification query -- worst delay causes by mode and month
SELECT
    f.mode, dd.month_name, dd.year,
    COUNT(*) AS delay_count,
    SUM(f.min_delay) AS total_delay_minutes,
    f.code_description
FROM FACT_DELAYS f
JOIN DIM_DATE dd ON f.delay_date = dd.full_date
GROUP BY f.mode, dd.month_name, dd.year, f.code_description
ORDER BY total_delay_minutes DESC
LIMIT 10;


-- ------------------------------------------------------------
-- 6. Automation -- stored procedure + daily scheduled Task
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE REFRESH_TTC_DATA()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  today STRING;
BEGIN
  today := TO_VARCHAR(CURRENT_DATE(), 'YYYY-MM-DD');

  TRUNCATE TABLE RAW_SUBWAY_DELAYS;
  TRUNCATE TABLE RAW_BUS_DELAYS;
  TRUNCATE TABLE RAW_STREETCAR_DELAYS;
  TRUNCATE TABLE RAW_SUBWAY_CODES;
  TRUNCATE TABLE RAW_BUS_CODES;
  TRUNCATE TABLE RAW_STREETCAR_CODES;

  EXECUTE IMMEDIATE 'COPY INTO RAW_SUBWAY_DELAYS (raw_data) FROM @TTC_RAW_STAGE/pull_date=' || :today || '/subway_delays.json FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT)';
  EXECUTE IMMEDIATE 'COPY INTO RAW_BUS_DELAYS (raw_data) FROM @TTC_RAW_STAGE/pull_date=' || :today || '/bus_delays.json FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT)';
  EXECUTE IMMEDIATE 'COPY INTO RAW_STREETCAR_DELAYS (raw_data) FROM @TTC_RAW_STAGE/pull_date=' || :today || '/streetcar_delays.json FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT)';
  EXECUTE IMMEDIATE 'COPY INTO RAW_SUBWAY_CODES (raw_data) FROM @TTC_RAW_STAGE/pull_date=' || :today || '/subway_delay_codes.json FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT)';
  EXECUTE IMMEDIATE 'COPY INTO RAW_BUS_CODES (raw_data) FROM @TTC_RAW_STAGE/pull_date=' || :today || '/bus_delay_codes.json FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT)';
  EXECUTE IMMEDIATE 'COPY INTO RAW_STREETCAR_CODES (raw_data) FROM @TTC_RAW_STAGE/pull_date=' || :today || '/streetcar_delay_codes.json FILE_FORMAT = (FORMAT_NAME = JSON_ARRAY_FORMAT)';

  CREATE OR REPLACE TABLE DIM_DELAY_CODE AS
  SELECT
      ROW_NUMBER() OVER (ORDER BY mode, delay_code) AS code_key,
      delay_code,
      REPLACE(code_description, 'â', '-') AS code_description,
      mode
  FROM STG_ALL_CODES;

  CREATE OR REPLACE TABLE FACT_DELAYS AS
  SELECT
      d.delay_id, d.mode, d.delay_date, d.delay_time, d.station,
      d.line, d.bound, d.vehicle, d.min_delay, d.min_gap,
      c.code_key, c.code_description
  FROM STG_ALL_DELAYS d
  LEFT JOIN DIM_DELAY_CODE c ON d.delay_code = c.delay_code AND d.mode = c.mode;

  RETURN 'Refresh complete for ' || :today;
END;
$$;

-- Test it manually once before trusting the schedule
CALL REFRESH_TTC_DATA();

CREATE OR REPLACE TASK DAILY_TTC_REFRESH
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 9 * * * UTC'
AS
  CALL REFRESH_TTC_DATA();

ALTER TASK DAILY_TTC_REFRESH RESUME;

-- Confirm the task is scheduled and running
SHOW TASKS LIKE 'DAILY_TTC_REFRESH';
