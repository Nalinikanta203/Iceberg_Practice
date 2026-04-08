-- =============================================================================
-- 03_data_operations.sql
-- Purpose : INSERT, UPDATE, DELETE, and MERGE on Snowflake-managed Iceberg
--           tables.  All DML operations are fully ACID — each statement
--           produces a new Iceberg snapshot atomically.
--
-- Prerequisites: run 01_setup.sql and 02_managed_iceberg_tables.sql first.
-- =============================================================================

USE WAREHOUSE ICEBERG_WH;
USE DATABASE  ICEBERG_DB;
USE SCHEMA    ICEBERG_SCHEMA;

-- ---------------------------------------------------------------------------
-- 1. INSERT rows
-- ---------------------------------------------------------------------------
INSERT INTO orders (order_id, customer_id, order_date, status, total_amount, region)
VALUES
    (1001, 201, '2024-01-10', 'PLACED',    150.00, 'WEST'),
    (1002, 202, '2024-01-11', 'PLACED',    320.50, 'EAST'),
    (1003, 203, '2024-01-12', 'SHIPPED',    89.99, 'WEST'),
    (1004, 204, '2024-01-13', 'DELIVERED', 475.25, 'CENTRAL'),
    (1005, 201, '2024-01-14', 'PLACED',    210.00, 'WEST');

-- Verify:
SELECT * FROM orders ORDER BY order_id;

-- INSERT … SELECT from a standard Snowflake (non-Iceberg) table or stage:
-- INSERT INTO orders SELECT * FROM staging.orders_stage WHERE order_date = CURRENT_DATE;

-- ---------------------------------------------------------------------------
-- 2. UPDATE rows
--    UPDATE is fully supported on Snowflake-managed Iceberg tables (V2 format
--    uses positional deletes under the hood).
-- ---------------------------------------------------------------------------
UPDATE orders
SET    status = 'SHIPPED'
WHERE  order_id IN (1001, 1002)
  AND  status = 'PLACED';

SELECT order_id, status FROM orders WHERE order_id IN (1001, 1002);

-- ---------------------------------------------------------------------------
-- 3. DELETE rows
--    DELETE also uses Iceberg V2 positional delete files — no full rewrite.
-- ---------------------------------------------------------------------------
DELETE FROM orders WHERE status = 'DELIVERED';

SELECT COUNT(*) AS remaining_rows FROM orders;

-- ---------------------------------------------------------------------------
-- 4. MERGE (upsert) — the most powerful DML pattern for Iceberg
--    Use MERGE to synchronise a source dataset into the target Iceberg table.
-- ---------------------------------------------------------------------------

-- Create a temporary source table to simulate incoming change data:
CREATE OR REPLACE TEMPORARY TABLE orders_updates (
    order_id        NUMBER(10, 0),
    customer_id     NUMBER(10, 0),
    order_date      DATE,
    status          VARCHAR(20),
    total_amount    NUMBER(12, 2),
    region          VARCHAR(30)
);

INSERT INTO orders_updates VALUES
    (1003, 203, '2024-01-12', 'DELIVERED', 89.99,  'WEST'),   -- update existing
    (1005, 201, '2024-01-14', 'CANCELLED', 210.00, 'WEST'),   -- update existing
    (1006, 205, '2024-01-15', 'PLACED',    599.00, 'EAST');   -- new row

MERGE INTO orders AS tgt
USING orders_updates AS src
    ON tgt.order_id = src.order_id
WHEN MATCHED AND src.status != tgt.status THEN
    UPDATE SET
        tgt.status       = src.status,
        tgt.total_amount = src.total_amount
WHEN NOT MATCHED THEN
    INSERT (order_id, customer_id, order_date, status, total_amount, region)
    VALUES (src.order_id, src.customer_id, src.order_date,
            src.status, src.total_amount, src.region);

SELECT * FROM orders ORDER BY order_id;

-- ---------------------------------------------------------------------------
-- 5. INSERT OVERWRITE (replace all rows in a partition)
--    Useful for full-refresh partition loads in pipelines.
-- ---------------------------------------------------------------------------
-- Example (events table is partitioned by day):
-- INSERT OVERWRITE INTO events
-- SELECT * FROM staging.events_stage WHERE event_ts::DATE = '2024-01-15';

-- ---------------------------------------------------------------------------
-- 6. Transactions — Snowflake wraps each DML in an implicit transaction.
--    You can also use explicit transactions:
-- ---------------------------------------------------------------------------
BEGIN TRANSACTION;
    UPDATE orders SET status = 'PROCESSING' WHERE status = 'PLACED';
    DELETE FROM orders WHERE order_id = 1006;
COMMIT;

-- Rollback example:
BEGIN TRANSACTION;
    DELETE FROM orders;   -- oops — delete everything
ROLLBACK;                 -- safe: no rows lost

SELECT COUNT(*) AS rows_after_rollback FROM orders;

-- ---------------------------------------------------------------------------
-- 7. Snowflake snapshot created by each DML commit
-- ---------------------------------------------------------------------------
-- After each DML Snowflake writes a new Iceberg snapshot.
-- The following metadata table shows the snapshot history:
SELECT *
FROM   TABLE(INFORMATION_SCHEMA.ICEBERG_SNAPSHOT_HISTORY(
                TABLE_NAME => 'orders',
                DATABASE_NAME => 'ICEBERG_DB',
                SCHEMA_NAME   => 'ICEBERG_SCHEMA'
             ))
ORDER BY committed_at DESC;
