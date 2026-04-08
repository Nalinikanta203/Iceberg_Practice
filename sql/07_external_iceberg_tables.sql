-- =============================================================================
-- 07_external_iceberg_tables.sql
-- Purpose : Register and query EXTERNALLY MANAGED Iceberg tables in Snowflake.
--
-- In this mode an external engine (Apache Spark, AWS Glue, Apache Flink, etc.)
-- owns the Iceberg metadata (catalog).  Snowflake reads the data without
-- taking ownership; DML (INSERT/UPDATE/DELETE) is NOT supported on these tables
-- unless they are converted to Snowflake-managed.
--
-- Two catalog integration types are shown:
--   A. AWS Glue Data Catalog
--   B. REST catalog (open standard, e.g. Apache Polaris / Gravitino)
--
-- Prerequisites: run 01_setup.sql first.
-- =============================================================================

USE WAREHOUSE ICEBERG_WH;
USE DATABASE  ICEBERG_DB;
USE SCHEMA    ICEBERG_SCHEMA;

-- ===========================================================================
-- A. AWS Glue Data Catalog Integration
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- A1. Create a Glue Catalog Integration
--     This tells Snowflake where the Glue catalog lives and which IAM role to
--     assume when browsing and reading metadata.
-- ---------------------------------------------------------------------------
CREATE CATALOG INTEGRATION IF NOT EXISTS glue_catalog_integration
    CATALOG_SOURCE          = GLUE
    CATALOG_NAMESPACE       = '<YOUR_GLUE_DATABASE>'      -- e.g. 'analytics_db'
    TABLE_FORMAT            = ICEBERG
    GLUE_AWS_ROLE_ARN       = 'arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/<YOUR_GLUE_ROLE>'
    GLUE_CATALOG_ID         = '<YOUR_AWS_ACCOUNT_ID>'
    GLUE_REGION             = 'us-east-1'
    ENABLED                 = TRUE;

DESC CATALOG INTEGRATION glue_catalog_integration;

-- ---------------------------------------------------------------------------
-- A2. Create an Iceberg table backed by an existing Glue table
-- ---------------------------------------------------------------------------
CREATE OR REPLACE ICEBERG TABLE glue_sales
    CATALOG             = 'glue_catalog_integration'
    CATALOG_TABLE_NAME  = 'sales'                         -- table name in Glue
    EXTERNAL_VOLUME     = 'ICEBERG_EXT_VOLUME';

-- ---------------------------------------------------------------------------
-- A3. Query the externally managed table
-- ---------------------------------------------------------------------------
SELECT *
FROM   glue_sales
LIMIT  100;

-- Refresh Snowflake's cached copy of the Iceberg metadata:
ALTER ICEBERG TABLE glue_sales REFRESH;

-- ---------------------------------------------------------------------------
-- A4. Auto-refresh via event notifications (recommended for production)
--     Instead of calling REFRESH manually, configure an SQS queue so that
--     Snowflake automatically syncs when the external engine commits a new
--     snapshot.
-- ---------------------------------------------------------------------------
-- ALTER ICEBERG TABLE glue_sales
--     SET CATALOG_AUTO_REFRESH = TRUE
--         AUTO_REFRESH_EVENT_NOTIFICATION_CONFIG =
--             'arn:aws:sqs:us-east-1:<YOUR_AWS_ACCOUNT_ID>:<YOUR_SQS_QUEUE>';

-- ===========================================================================
-- B. REST Catalog Integration (Apache Polaris / Gravitino / Tabular, etc.)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- B1. Create the REST Catalog Integration
-- ---------------------------------------------------------------------------
CREATE CATALOG INTEGRATION IF NOT EXISTS rest_catalog_integration
    CATALOG_SOURCE      = ICEBERG_REST
    CATALOG_NAMESPACE   = 'default'
    TABLE_FORMAT        = ICEBERG
    CATALOG_URI         = 'https://<YOUR_REST_CATALOG_ENDPOINT>/api/catalog'
    REST_CONFIG         = ('SECURITY' = 'NONE')           -- or OAUTH, BEARER, etc.
    ENABLED             = TRUE;

-- ---------------------------------------------------------------------------
-- B2. Create a table backed by the REST catalog
-- ---------------------------------------------------------------------------
CREATE OR REPLACE ICEBERG TABLE rest_events
    CATALOG             = 'rest_catalog_integration'
    CATALOG_NAMESPACE   = 'default'
    CATALOG_TABLE_NAME  = 'events'
    EXTERNAL_VOLUME     = 'ICEBERG_EXT_VOLUME';

SELECT COUNT(*) FROM rest_events;

-- ===========================================================================
-- C. Convert an External Iceberg Table to Snowflake-managed
--    Once converted, Snowflake takes over metadata management and full DML
--    (UPDATE, DELETE, MERGE) becomes available.
--    NOTE: This operation is one-way and cannot be reversed.
-- ===========================================================================
ALTER ICEBERG TABLE glue_sales
    CONVERT TO MANAGED
    BASE_LOCATION = 'glue_sales/';          -- new base path for Snowflake metadata

-- Verify:
SHOW ICEBERG TABLES LIKE 'glue_sales';

-- Now DML is available:
UPDATE glue_sales SET region = 'US-EAST' WHERE country = 'US';

-- ===========================================================================
-- D. Sharing Snowflake-managed Iceberg tables with external engines
--    After Snowflake writes a snapshot, the open Parquet files can be read by
--    any Iceberg-compatible engine using the metadata_location.
-- ===========================================================================

-- Get the current metadata.json path for the table:
SELECT PARSE_JSON(SYSTEM$ICEBERG_METADATA('ICEBERG_DB.ICEBERG_SCHEMA.orders'))
           :current_metadata_location::STRING AS metadata_location;

-- An external engine (Spark example — run outside Snowflake):
-- spark.read
--     .format("iceberg")
--     .option("path", "<metadata_location>")
--     .load()
--     .show(10)
