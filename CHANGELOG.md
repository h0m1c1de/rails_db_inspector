# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
