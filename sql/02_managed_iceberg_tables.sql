-- =============================================================================
-- 02_managed_iceberg_tables.sql
-- Purpose : Create and inspect Snowflake-managed Iceberg tables.
--
-- In this mode Snowflake writes Iceberg metadata (manifests, snapshot JSON,
-- catalog files) automatically every time a DML statement commits.
-- Data is stored as Parquet in YOUR external volume — Snowflake never stores
-- the actual files internally.
--
-- Prerequisites: run 01_setup.sql first.
-- =============================================================================

USE WAREHOUSE ICEBERG_WH;
USE DATABASE  ICEBERG_DB;
USE SCHEMA    ICEBERG_SCHEMA;

-- ---------------------------------------------------------------------------
-- 1. Create a simple Iceberg table (Snowflake-managed)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE ICEBERG TABLE orders (
    order_id        NUMBER(10, 0)   NOT NULL,
    customer_id     NUMBER(10, 0)   NOT NULL,
    order_date      DATE            NOT NULL,
    status          VARCHAR(20)     NOT NULL,
    total_amount    NUMBER(12, 2),
    region          VARCHAR(30)
)
    CATALOG             = 'SNOWFLAKE'           -- Snowflake manages Iceberg metadata
    EXTERNAL_VOLUME     = 'ICEBERG_EXT_VOLUME'
    BASE_LOCATION       = 'orders/'             -- sub-path within the external volume
    COMMENT             = 'Customer orders — Snowflake-managed Iceberg table';

-- ---------------------------------------------------------------------------
-- 2. Create a partitioned Iceberg table
--    Snowflake uses hidden partitioning: the partition column is defined in
--    the table spec but users do NOT need to include it in every query.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE ICEBERG TABLE events (
    event_id        NUMBER(18, 0)   NOT NULL,
    user_id         NUMBER(10, 0)   NOT NULL,
    event_type      VARCHAR(50)     NOT NULL,
    event_ts        TIMESTAMP_NTZ   NOT NULL,
    payload         VARIANT,
    country_code    VARCHAR(3)
)
    CATALOG             = 'SNOWFLAKE'
    EXTERNAL_VOLUME     = 'ICEBERG_EXT_VOLUME'
    BASE_LOCATION       = 'events/'
    -- Partition by the DAY of event_ts so that each day's data is co-located:
    PARTITION BY (DATE_TRUNC('DAY', event_ts))
    COMMENT             = 'User events partitioned by day — Snowflake-managed Iceberg';

-- ---------------------------------------------------------------------------
-- 3. Create an Iceberg table with CLUSTERING
--    Clustering keeps data with similar key values in the same micro-partitions,
--    dramatically reducing scan costs for selective queries.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE ICEBERG TABLE products (
    product_id      NUMBER(10, 0)   NOT NULL,
    category        VARCHAR(60)     NOT NULL,
    sub_category    VARCHAR(60),
    name            VARCHAR(200)    NOT NULL,
    price           NUMBER(10, 2),
    stock_qty       NUMBER(10, 0)   DEFAULT 0,
    created_at      TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
)
    CATALOG             = 'SNOWFLAKE'
    EXTERNAL_VOLUME     = 'ICEBERG_EXT_VOLUME'
    BASE_LOCATION       = 'products/'
    CLUSTER BY (category)       -- automatic clustering on category
    COMMENT             = 'Product catalogue with clustering on category';

-- ---------------------------------------------------------------------------
-- 4. Inspect the tables
-- ---------------------------------------------------------------------------

-- List all Iceberg tables in the current schema:
SHOW ICEBERG TABLES;

-- Show DDL of a specific table:
SELECT GET_DDL('TABLE', 'orders');

-- Describe column definitions:
DESCRIBE TABLE events;

-- ---------------------------------------------------------------------------
-- 5. Show Iceberg-specific table properties
-- ---------------------------------------------------------------------------
SHOW TERSE ICEBERG TABLES LIKE 'orders';

-- ---------------------------------------------------------------------------
-- 6. Alter table properties (change external volume, base location is immutable)
-- ---------------------------------------------------------------------------
-- ALTER ICEBERG TABLE orders SET EXTERNAL_VOLUME = 'ICEBERG_EXT_VOLUME';

-- ---------------------------------------------------------------------------
-- 7. Dropping Iceberg tables
--    DROP removes the Snowflake metadata reference; Parquet files in your
--    external volume are NOT automatically deleted.
-- ---------------------------------------------------------------------------
-- DROP ICEBERG TABLE IF EXISTS orders;
