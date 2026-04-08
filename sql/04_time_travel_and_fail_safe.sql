-- =============================================================================
-- 04_time_travel_and_fail_safe.sql
-- Purpose : Demonstrate Time Travel on Snowflake-managed Iceberg tables.
--
-- Key difference from standard Snowflake tables:
--   - Time travel retention is set via DATA_RETENTION_TIME_IN_DAYS (default 1,
--     max 90 days for Snowflake-managed Iceberg tables).
--   - Fail-safe (7-day non-configurable recovery window) is NOT available for
--     Iceberg tables — data recovery beyond the retention window is the
--     customer's responsibility using the files in external storage.
--
-- Prerequisites: run 01_setup.sql → 03_data_operations.sql first.
-- =============================================================================

USE WAREHOUSE ICEBERG_WH;
USE DATABASE  ICEBERG_DB;
USE SCHEMA    ICEBERG_SCHEMA;

-- ---------------------------------------------------------------------------
-- 1. Verify current time travel setting on the orders table
-- ---------------------------------------------------------------------------
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE orders;

-- Increase retention to 7 days:
ALTER TABLE orders SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- ---------------------------------------------------------------------------
-- 2. Note the current time BEFORE making changes
-- ---------------------------------------------------------------------------
SET before_change_ts = CURRENT_TIMESTAMP();

-- ---------------------------------------------------------------------------
-- 3. Make a change we want to undo later
-- ---------------------------------------------------------------------------
UPDATE orders SET region = 'UNKNOWN' WHERE region = 'WEST';
SELECT order_id, region FROM orders;

-- ---------------------------------------------------------------------------
-- 4. Time-travel query using TIMESTAMP
--    AT (TIMESTAMP => ...) reads the snapshot that was current at that moment.
-- ---------------------------------------------------------------------------
SELECT order_id, region
FROM   orders AT (TIMESTAMP => $before_change_ts)
ORDER  BY order_id;

-- ---------------------------------------------------------------------------
-- 5. Time-travel query using OFFSET (seconds before now)
-- ---------------------------------------------------------------------------
-- Read the table as it was 5 minutes ago:
SELECT COUNT(*) AS row_count_5_min_ago
FROM   orders AT (OFFSET => -300);

-- ---------------------------------------------------------------------------
-- 6. Time-travel query using a specific SNAPSHOT ID
--    Snapshot IDs come from ICEBERG_SNAPSHOT_HISTORY.
-- ---------------------------------------------------------------------------
-- Step 1 – get available snapshots:
SELECT snapshot_id, committed_at, operation, summary
FROM   TABLE(INFORMATION_SCHEMA.ICEBERG_SNAPSHOT_HISTORY(
                TABLE_NAME    => 'orders',
                DATABASE_NAME => 'ICEBERG_DB',
                SCHEMA_NAME   => 'ICEBERG_SCHEMA'
             ))
ORDER  BY committed_at DESC;

-- Step 2 – query a specific snapshot (replace <SNAPSHOT_ID> with the real value):
-- SELECT * FROM orders AT (STATEMENT => '<SNAPSHOT_ID>');

-- ---------------------------------------------------------------------------
-- 7. Restore ("undo") using CLONE + SWAP — a common recovery pattern
-- ---------------------------------------------------------------------------
-- Create a zero-copy clone from a point before the bad UPDATE:
CREATE OR REPLACE TABLE orders_restored
    CLONE orders AT (TIMESTAMP => $before_change_ts);

-- Verify the restored clone has original data:
SELECT order_id, region FROM orders_restored ORDER BY order_id;

-- Swap the bad table with the restored one (atomic rename):
ALTER TABLE orders          RENAME TO orders_bad;
ALTER TABLE orders_restored RENAME TO orders;
DROP TABLE IF EXISTS orders_bad;

-- Confirm:
SELECT order_id, region FROM orders ORDER BY order_id;

-- ---------------------------------------------------------------------------
-- 8. UNDROP — recover a dropped Iceberg table within the retention window
-- ---------------------------------------------------------------------------
DROP TABLE orders;

-- The table is gone for normal queries:
-- SELECT * FROM orders;  -- would fail

-- Recover it:
UNDROP TABLE orders;

SELECT COUNT(*) AS recovered_rows FROM orders;

-- ---------------------------------------------------------------------------
-- 9. Fail-Safe Note
--    Standard Snowflake tables have a 7-day fail-safe period after time travel
--    expires, during which Snowflake support can recover data.
--    Iceberg tables do NOT have this Snowflake-managed fail-safe.
--    Best practice: enable versioning on your S3/Azure/GCS bucket so you can
--    recover Parquet and metadata files independently.
-- ---------------------------------------------------------------------------
