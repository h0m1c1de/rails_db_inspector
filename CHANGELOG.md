# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-02-24

### Added

- STI index detection — suggests index on `type` column for Single Table Inheritance models
- Uniqueness validation index detection — identifies `validates_uniqueness_of` without a matching database unique index
- Covering index suggestions — analyzes WHERE + ORDER BY query patterns to suggest composite covering indexes
- Partial boolean index suggestions — detects skewed boolean columns and recommends partial indexes on the minority value
- Redundant index detection — identifies indexes that are prefix-redundant with longer composite indexes
- Soft-delete partial index suggestions — detects `deleted_at`/`discarded_at`/`archived_at` columns and recommends `WHERE ... IS NULL` partial indexes
- Timestamp ordering index suggestions — identifies `created_at`/`updated_at` columns frequently used in ORDER BY without an index
- Counter cache sorting index suggestions — detects `_count` columns used in ORDER BY for leaderboard-style queries
- SQLite EXPLAIN QUERY PLAN support — full EXPLAIN support for SQLite databases
- `extract_order_columns` now filters out table name tokens from single-table ORDER BY clauses

### Fixed

- `detect_redundant_indexes` no longer flags unique indexes as redundant

## [0.2.0] - 2026-02-24

### Added

- Polymorphic composite index suggestions — recommends `[type, id]` indexes for polymorphic associations
- Query-driven index suggestions — analyzes captured SQL queries to recommend composite indexes based on WHERE/ORDER BY usage patterns
- Join table composite index suggestions — detects join tables and recommends composite (and unique) indexes on foreign key pairs
- Index suggestions displayed in schema detail panel with copy-to-clipboard SQL and Rails migration commands
- Index suggestion badges on ERD nodes, sidebar items, and health bar
- Automated release workflow via GitHub Actions

### Fixed

- Flaky `parse_timestamp` test that relied on `Time.parse` behavior varying across Ruby versions

## [0.1.0] - 2026-02-23

### Added

- Initial release
- SQL query capture and monitoring dashboard
- N+1 query detection
- EXPLAIN / EXPLAIN ANALYZE support (PostgreSQL and MySQL)
- Interactive schema visualization (ERD) with force-directed layout
- Missing index detection on foreign key columns
- Polymorphic association detection
- Schema health bar with table stats
- Development widget overlay middleware
- Configurable via `RailsDbInspector.configure`
