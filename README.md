# Snowflake Iceberg — Deep Dive Practice

A hands-on reference repository for learning **Apache Iceberg on Snowflake**.  
Work through the numbered SQL scripts in the `sql/` folder to build a solid, end-to-end understanding of how Snowflake implements and extends the Apache Iceberg open table format.

---

## What Is Apache Iceberg?

[Apache Iceberg](https://iceberg.apache.org/) is an open, high-performance table format designed for large analytic datasets. It brings **ACID transactions**, **schema evolution**, **hidden partitioning**, and **time travel** to data stored in cloud object storage (S3, GCS, Azure ADLS).

---

## Snowflake and Iceberg

Snowflake supports Iceberg tables in two modes:

| Mode | Who Manages Metadata | Storage |
|------|---------------------|---------|
| **Snowflake-managed** | Snowflake (writes Iceberg metadata automatically) | External cloud storage you own |
| **Externally managed** | External engine (Spark, Flink, etc.) | External cloud storage you own |

Both modes store data as **open Parquet files** using the Iceberg V2 format, making the data accessible to any Iceberg-compatible engine.

---

## Repository Structure

```
sql/
├── 01_setup.sql                     # Warehouses, databases, schemas, storage integrations
├── 02_managed_iceberg_tables.sql    # Create & configure Snowflake-managed Iceberg tables
├── 03_data_operations.sql           # INSERT, UPDATE, DELETE, MERGE
├── 04_time_travel_and_fail_safe.sql # Time travel queries, UNDROP, fail-safe overview
├── 05_schema_evolution.sql          # ADD / DROP / RENAME columns, type promotion
├── 06_metadata_and_optimization.sql # Metadata queries, clustering, OPTIMIZE / compaction
└── 07_external_iceberg_tables.sql   # Read externally managed Iceberg tables in Snowflake
```

---

## Key Concepts Covered

1. **Storage Integration** — Delegate cloud storage access to Snowflake securely without storing credentials.
2. **External Volume** — Snowflake object that points to the cloud storage location for Iceberg data files.
3. **Iceberg Table Creation** — `CREATE ICEBERG TABLE` syntax, base location, catalog options.
4. **DML on Iceberg Tables** — Full ANSI SQL `INSERT`, `UPDATE`, `DELETE`, and `MERGE` support.
5. **Time Travel** — Query historical snapshots using `AT (TIMESTAMP =>…)` or `AT (OFFSET =>…)`.
6. **Schema Evolution** — Add, drop, and rename columns without rewriting data files.
7. **Clustering** — Automatic and manual clustering to minimise data scanned.
8. **Metadata & Optimization** — `SYSTEM$ICEBERG_METADATA`, `ALTER TABLE … OPTIMIZE`, compaction.
9. **External Iceberg Tables** — Register tables whose metadata was written by external engines.
10. **Interoperability** — How other engines (Spark, AWS Athena, etc.) can read Snowflake-managed Iceberg tables.

---

## Prerequisites

- A Snowflake account with `ACCOUNTADMIN` (or a custom role with `CREATE INTEGRATION` privilege).
- An S3 bucket (or Azure/GCS equivalent) dedicated to Iceberg data — called `<YOUR_BUCKET>` in the scripts.
- AWS IAM role (or Azure Service Principal / GCS Service Account) that Snowflake will assume.

---

## Getting Started

1. Open a Snowflake worksheet or SnowSQL session.
2. Run `sql/01_setup.sql` to create all required account-level objects.
3. Replace every placeholder (`<YOUR_BUCKET>`, `<YOUR_AWS_ACCOUNT_ID>`, etc.) with your own values.
4. Work through scripts `02` → `07` in order.

---

## Useful Documentation Links

- [Snowflake Iceberg Tables overview](https://docs.snowflake.com/en/user-guide/tables-iceberg)
- [CREATE ICEBERG TABLE](https://docs.snowflake.com/en/sql-reference/sql/create-iceberg-table)
- [External Volumes](https://docs.snowflake.com/en/user-guide/tables-iceberg-configure-external-volume)
- [Apache Iceberg specification](https://iceberg.apache.org/spec/)

---

## License

This repository is provided for educational purposes.
