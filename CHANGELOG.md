# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-02-24

### Added

- **SQL Console** — interactive SQL query console with syntax awareness, query history, table browser, and keyboard shortcuts (⌘+Enter to run)
  - Read-only by default; configurable with `allow_console_writes` option
  - DDL statements (DROP, TRUNCATE, ALTER, CREATE, GRANT, REVOKE) always blocked
  - Results displayed in sortable table with NULL value styling
- **Slow Query Log** — dedicated slow query panel on the Query Monitor page ranking queries by duration
  - Filter toolbar with preset thresholds (All, >100ms, >1s) and custom threshold input
  - Client-side duration sorting (slowest first, fastest first, by time)
  - Filter summary banner showing visible/total counts
  - Top 20 slow queries displayed with rank, duration badges, and quick links to View/Explain
- **Table Size Stats** — per-table disk usage displayed in schema ERD
  - Supports PostgreSQL (`pg_total_relation_size`), MySQL (`information_schema.TABLES`), and SQLite (`dbstat`)
  - Data/index size breakdown with visual bar chart in detail panel
  - Total database size, largest table, and data/index ratio in health bar sidebar
  - Table sizes shown on ERD node headers and sidebar items
- **EXPLAIN Page Overhaul** — educational reading guide, verdict card (good/ok/bad), node type glossary, column tooltips with color-coded cells, "What to Do Next" section
- **ANALYZE from EXPLAIN page** — run ANALYZE on any table via dropdown directly from the explain page
- Console navigation link added to all pages

### Changed

- Renamed "Execution Summary" to "Performance Metrics" on explain pages
- Query Monitor table rows now carry data-duration attributes for client-side filtering

## [0.5.0] - 2026-02-24

### Added

- Schema loading overlay with animated spinner and live elapsed timer
- Table and relationship count shown during layout
- Overlay auto-hides with fade transition once force-directed layout settles

### Changed

- Updated gem description to include smart index suggestions and SQLite support

## [0.4.0] - 2026-02-24

### Added

- SQLite EXPLAIN QUERY PLAN support — full EXPLAIN support for SQLite databases

## [0.3.0] - 2026-02-24

### Added

- STI index detection — suggests index on `type` column for Single Table Inheritance models
- Uniqueness validation index detection — identifies `validates_uniqueness_of` without a matching database unique index
- Covering index suggestions — analyzes WHERE + ORDER BY query patterns to suggest composite covering indexes
- Partial boolean index suggestions — detects skewed boolean columns and recommends partial indexes on the minority value
- Redundant index detection — identifies indexes that are prefix-redundant with longer composite indexes
- Soft-delete partial index suggestions — detects `deleted_at`/`discarded_at`/`archived_at` columns and recommends `WHERE ... IS NULL` partial indexes
- Timestamp ordering index suggestions — identifies `created_at`/`updated_at` columns frequently used in ORDER BY without an index
- Counter cache sorting index suggestions — detects `_count` columns used in ORDER BY for leaderboard-style queries
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
