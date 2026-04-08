-- =============================================================================
-- 01_setup.sql
-- Purpose : Create all account-level objects required for Iceberg practice.
--           Run this script once with ACCOUNTADMIN (or equivalent privilege).
--
-- Replace every <PLACEHOLDER> with values specific to your environment.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Virtual Warehouse
-- ---------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS ICEBERG_WH
    WAREHOUSE_SIZE   = 'X-SMALL'
    AUTO_SUSPEND     = 60
    AUTO_RESUME      = TRUE
    COMMENT          = 'Warehouse for Iceberg practice';

USE WAREHOUSE ICEBERG_WH;

-- ---------------------------------------------------------------------------
-- 2. Database and Schema
-- ---------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS ICEBERG_DB
    COMMENT = 'Database for Snowflake Iceberg deep dive';

CREATE SCHEMA IF NOT EXISTS ICEBERG_DB.ICEBERG_SCHEMA
    COMMENT = 'Schema holding all Iceberg practice tables';

USE DATABASE ICEBERG_DB;
USE SCHEMA   ICEBERG_SCHEMA;

-- ---------------------------------------------------------------------------
-- 3. Storage Integration (AWS S3 example)
--
-- A Storage Integration lets Snowflake assume an IAM role in your AWS account
-- instead of storing long-lived access keys inside Snowflake.
--
-- Docs: https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration
-- ---------------------------------------------------------------------------
CREATE STORAGE INTEGRATION IF NOT EXISTS ICEBERG_S3_INTEGRATION
    TYPE                      = EXTERNAL_STAGE
    STORAGE_PROVIDER          = 'S3'
    ENABLED                   = TRUE
    STORAGE_AWS_ROLE_ARN      = 'arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/<YOUR_IAM_ROLE>'
    STORAGE_ALLOWED_LOCATIONS = ('s3://<YOUR_BUCKET>/iceberg/');

-- After creating the integration, retrieve the Snowflake IAM values that must
-- be added to your AWS IAM trust policy:
DESC INTEGRATION ICEBERG_S3_INTEGRATION;
-- Note the values of:
--   STORAGE_AWS_IAM_USER_ARN   → add as a principal in the IAM trust policy
--   STORAGE_AWS_EXTERNAL_ID    → use as the condition ExternalId in the trust policy

-- ---------------------------------------------------------------------------
-- 4. External Volume
--
-- An External Volume points to the cloud storage path where Iceberg will write
-- data and metadata files.  It references the Storage Integration above.
--
-- Docs: https://docs.snowflake.com/en/user-guide/tables-iceberg-configure-external-volume
-- ---------------------------------------------------------------------------
CREATE EXTERNAL VOLUME IF NOT EXISTS ICEBERG_EXT_VOLUME
    STORAGE_LOCATIONS = (
        (
            NAME                  = 'iceberg-s3-loc'
            STORAGE_PROVIDER      = 'S3'
            STORAGE_BASE_URL      = 's3://<YOUR_BUCKET>/iceberg/'
            STORAGE_AWS_ROLE_ARN  = 'arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/<YOUR_IAM_ROLE>'
        )
    );

-- Validate the external volume is accessible:
DESC EXTERNAL VOLUME ICEBERG_EXT_VOLUME;
SHOW EXTERNAL VOLUMES;

-- ---------------------------------------------------------------------------
-- 5. (Optional) Role and Grants for a non-ACCOUNTADMIN role
-- ---------------------------------------------------------------------------
-- CREATE ROLE IF NOT EXISTS ICEBERG_ROLE;
-- GRANT USAGE  ON WAREHOUSE    ICEBERG_WH                    TO ROLE ICEBERG_ROLE;
-- GRANT USAGE  ON DATABASE     ICEBERG_DB                    TO ROLE ICEBERG_ROLE;
-- GRANT ALL    ON SCHEMA       ICEBERG_DB.ICEBERG_SCHEMA     TO ROLE ICEBERG_ROLE;
-- GRANT USAGE  ON INTEGRATION  ICEBERG_S3_INTEGRATION        TO ROLE ICEBERG_ROLE;
-- GRANT USAGE  ON EXTERNAL VOLUME ICEBERG_EXT_VOLUME         TO ROLE ICEBERG_ROLE;
