-- =============================================================================
-- 05_schema_evolution.sql
-- Purpose : Demonstrate schema evolution on Snowflake-managed Iceberg tables.
--
-- Apache Iceberg natively supports schema evolution: you can add, drop, rename,
-- and reorder columns, as well as promote certain data types — all WITHOUT
-- rewriting existing Parquet data files.
--
-- Snowflake exposes full schema evolution through standard ALTER TABLE syntax.
--
-- Prerequisites: run 01_setup.sql and 02_managed_iceberg_tables.sql first.
-- =============================================================================

USE WAREHOUSE ICEBERG_WH;
USE DATABASE  ICEBERG_DB;
USE SCHEMA    ICEBERG_SCHEMA;

-- Baseline column layout:
DESCRIBE TABLE orders;

-- ---------------------------------------------------------------------------
-- 1. ADD COLUMN
--    New column is NULL for all existing rows (no data rewrite).
-- ---------------------------------------------------------------------------
ALTER TABLE orders ADD COLUMN discount_pct  NUMBER(5, 2);
ALTER TABLE orders ADD COLUMN updated_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
ALTER TABLE orders ADD COLUMN tags          ARRAY;

DESCRIBE TABLE orders;
SELECT order_id, discount_pct, updated_at, tags FROM orders LIMIT 5;

-- ---------------------------------------------------------------------------
-- 2. DROP COLUMN
--    The column is removed from the Iceberg schema.  Existing Parquet files
--    still physically contain the data, but Iceberg readers will ignore it.
-- ---------------------------------------------------------------------------
ALTER TABLE orders DROP COLUMN tags;

DESCRIBE TABLE orders;

-- ---------------------------------------------------------------------------
-- 3. RENAME COLUMN
--    Only the schema metadata changes — no file rewrite.
-- ---------------------------------------------------------------------------
ALTER TABLE orders RENAME COLUMN discount_pct TO discount_percent;

DESCRIBE TABLE orders;
SELECT order_id, discount_percent FROM orders LIMIT 5;

-- ---------------------------------------------------------------------------
-- 4. TYPE WIDENING (type promotion)
--    Iceberg V2 allows certain safe promotions that do not change stored bytes:
--      int  → long (bigint)
--      float → double
--      decimal(p,s) → decimal(p+x, s)  (widen precision only)
--    Snowflake supports compatible promotions via ALTER TABLE … ALTER COLUMN.
-- ---------------------------------------------------------------------------
-- Promote total_amount from NUMBER(12,2) to NUMBER(18,2):
ALTER TABLE orders ALTER COLUMN total_amount SET DATA TYPE NUMBER(18, 2);

DESCRIBE TABLE orders;

-- ---------------------------------------------------------------------------
-- 5. SET / DROP column DEFAULT and NOT NULL constraint
-- ---------------------------------------------------------------------------
ALTER TABLE orders ALTER COLUMN discount_percent SET DEFAULT 0.00;
ALTER TABLE orders ALTER COLUMN discount_percent DROP DEFAULT;

-- ---------------------------------------------------------------------------
-- 6. ADD COLUMN with a COMMENT
-- ---------------------------------------------------------------------------
ALTER TABLE orders ADD COLUMN shipping_address VARCHAR(500)
    COMMENT 'Full shipping address as a single string';

DESCRIBE TABLE orders;

-- ---------------------------------------------------------------------------
-- 7. Changing column order (FIRST / AFTER <col>)
--    Iceberg tracks column order in schema metadata; existing files are unaffected.
-- ---------------------------------------------------------------------------
-- Not yet supported via ALTER TABLE in Snowflake; column ordering follows
-- the order of ADD COLUMN statements or the original CREATE TABLE.

-- ---------------------------------------------------------------------------
-- 8. Schema evolution on the events table (VARIANT column)
--    Adding a top-level column alongside a VARIANT payload is a common pattern
--    when you want to "promote" frequently accessed JSON keys to first-class columns.
-- ---------------------------------------------------------------------------
ALTER TABLE events ADD COLUMN session_id VARCHAR(64);
ALTER TABLE events ADD COLUMN device_type VARCHAR(30);

DESCRIBE TABLE events;

-- ---------------------------------------------------------------------------
-- 9. Verify backward compatibility — old snapshots still readable
--    Time-travel queries against older snapshots return the schema at that
--    snapshot (columns added later show NULL, dropped columns are absent).
-- ---------------------------------------------------------------------------
-- SELECT * FROM orders AT (OFFSET => -300) LIMIT 5;
