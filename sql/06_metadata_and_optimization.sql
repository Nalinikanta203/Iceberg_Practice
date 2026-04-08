-- =============================================================================
-- 06_metadata_and_optimization.sql
-- Purpose : Explore Iceberg metadata, clustering, and optimization (compaction).
--
-- Topics covered:
--   • Reading Iceberg metadata tables (snapshots, manifests, files)
--   • Automatic and manual clustering
--   • OPTIMIZE (file compaction) to reduce small-file overhead
--   • Monitoring table health
--
-- Prerequisites: run 01_setup.sql → 05_schema_evolution.sql first.
-- =============================================================================

USE WAREHOUSE ICEBERG_WH;
USE DATABASE  ICEBERG_DB;
USE SCHEMA    ICEBERG_SCHEMA;

-- ---------------------------------------------------------------------------
-- 1. Iceberg Metadata: Snapshot History
--    Every DML commit creates a new snapshot.  Each snapshot records:
--      • operation (append, overwrite, delete, replace)
--      • snapshot_id (unique 64-bit integer)
--      • manifest_list path in external storage
--      • summary stats (added/deleted files, rows)
-- ---------------------------------------------------------------------------
SELECT *
FROM   TABLE(INFORMATION_SCHEMA.ICEBERG_SNAPSHOT_HISTORY(
                TABLE_NAME    => 'orders',
                DATABASE_NAME => 'ICEBERG_DB',
                SCHEMA_NAME   => 'ICEBERG_SCHEMA'
             ))
ORDER  BY committed_at DESC;

-- ---------------------------------------------------------------------------
-- 2. Iceberg Metadata: Manifest Files
--    Each snapshot references one or more manifest files.  A manifest lists
--    the data (and delete) files that belong to the snapshot, along with
--    per-column statistics (min/max, null counts) used for file pruning.
-- ---------------------------------------------------------------------------
SELECT *
FROM   TABLE(INFORMATION_SCHEMA.ICEBERG_MANIFESTS(
                TABLE_NAME    => 'orders',
                DATABASE_NAME => 'ICEBERG_DB',
                SCHEMA_NAME   => 'ICEBERG_SCHEMA'
             ))
ORDER  BY added_snapshot_id DESC;

-- ---------------------------------------------------------------------------
-- 3. Iceberg Metadata: Data Files
--    Lists every Parquet data file referenced by the CURRENT snapshot,
--    along with file size, row count, and per-column stats.
-- ---------------------------------------------------------------------------
SELECT *
FROM   TABLE(INFORMATION_SCHEMA.ICEBERG_FILES(
                TABLE_NAME    => 'orders',
                DATABASE_NAME => 'ICEBERG_DB',
                SCHEMA_NAME   => 'ICEBERG_SCHEMA'
             ))
ORDER  BY file_path;

-- ---------------------------------------------------------------------------
-- 4. SYSTEM$ICEBERG_METADATA helper function
--    Returns a quick health summary of the table as a VARIANT.
-- ---------------------------------------------------------------------------
SELECT PARSE_JSON(
    SYSTEM$ICEBERG_METADATA(
        'ICEBERG_DB.ICEBERG_SCHEMA.orders'
    )
) AS metadata_summary;

-- ---------------------------------------------------------------------------
-- 5. Table Storage Usage
-- ---------------------------------------------------------------------------
SELECT  table_name,
        active_bytes / POWER(1024, 3)             AS active_gb,
        time_travel_bytes / POWER(1024, 3)        AS time_travel_gb,
        failsafe_bytes / POWER(1024, 3)           AS failsafe_gb,
        retained_for_clone_bytes / POWER(1024, 3) AS clone_retained_gb
FROM    INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE   table_schema = 'ICEBERG_SCHEMA'
ORDER   BY active_bytes DESC;

-- ---------------------------------------------------------------------------
-- 6. Clustering
--    Automatic clustering keeps data physically sorted on the cluster key,
--    which minimises micro-partitions scanned for selective queries.
--    For Iceberg tables, Snowflake rewrites files during OPTIMIZE to sort by
--    the clustering key.
-- ---------------------------------------------------------------------------

-- Add a cluster key to an existing table:
ALTER TABLE orders CLUSTER BY (region);

-- Check clustering information:
SELECT SYSTEM$CLUSTERING_INFORMATION('orders', '(region)');

-- Optionally define a cluster key with a transformation:
ALTER TABLE events CLUSTER BY (DATE_TRUNC('MONTH', event_ts));

-- Remove clustering:
-- ALTER TABLE orders DROP CLUSTERING KEY;

-- Suspend / Resume automatic clustering:
ALTER TABLE orders SUSPEND RECLUSTER;
ALTER TABLE orders RESUME  RECLUSTER;

-- ---------------------------------------------------------------------------
-- 7. OPTIMIZE (file compaction)
--    Compaction merges many small Parquet files into fewer larger files.
--    It also rewrites delete files (positional deletes) back into data files,
--    reducing read amplification.
--
--    Syntax: ALTER ICEBERG TABLE <name> OPTIMIZE [ FULL ]
-- ---------------------------------------------------------------------------

-- Compact files that are below 512 MB (Snowflake default threshold):
ALTER ICEBERG TABLE orders OPTIMIZE;

-- FULL compaction — rewrites ALL files, not just small ones.
-- Use after heavy UPDATE/DELETE workloads to eliminate delete files entirely:
ALTER ICEBERG TABLE orders OPTIMIZE FULL;

-- ---------------------------------------------------------------------------
-- 8. Verify compaction effect
--    The number of data files should decrease, file sizes should increase.
-- ---------------------------------------------------------------------------
SELECT  COUNT(*)            AS file_count,
        SUM(file_size_bytes) / POWER(1024, 2) AS total_size_mb,
        AVG(file_size_bytes) / POWER(1024, 2) AS avg_file_size_mb
FROM    TABLE(INFORMATION_SCHEMA.ICEBERG_FILES(
                TABLE_NAME    => 'orders',
                DATABASE_NAME => 'ICEBERG_DB',
                SCHEMA_NAME   => 'ICEBERG_SCHEMA'
             ));

-- ---------------------------------------------------------------------------
-- 9. Query Profile & partition pruning
--    Enable the query profiler to see how many files were pruned vs scanned.
-- ---------------------------------------------------------------------------
SELECT order_id, status, total_amount
FROM   orders
WHERE  region = 'WEST'
  AND  order_date BETWEEN '2024-01-01' AND '2024-06-30';

-- In the query profile (UI or QUERY_HISTORY), look for:
--   "Partitions scanned" vs "Partitions total"
--   "Files scanned" vs "Files total"

-- ---------------------------------------------------------------------------
-- 10. Expire old snapshots (catalog maintenance)
--     Iceberg retains all snapshots by default, which can accumulate metadata.
--     Use ALTER TABLE … EXPIRE SNAPSHOTS to remove snapshots older than a
--     given timestamp (the underlying Parquet files are NOT deleted by this —
--     they can only be deleted after GC in external storage).
-- ---------------------------------------------------------------------------
ALTER ICEBERG TABLE orders EXPIRE SNAPSHOTS OLDER THAN (DATEADD('DAY', -30, CURRENT_TIMESTAMP()));
