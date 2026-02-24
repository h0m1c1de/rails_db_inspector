# Rails DB Inspector

A mountable Rails engine that gives you a built-in dashboard for **SQL query monitoring**, **N+1 detection**, **EXPLAIN / EXPLAIN ANALYZE plans**, and **interactive schema visualization** — no external services required.

Supports **PostgreSQL** and **MySQL**.

![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-red)
![Rails](https://img.shields.io/badge/rails-%3E%3D%207.1-red)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Gem Version](https://badge.fury.io/rb/rails_db_inspector.svg)](https://rubygems.org/gems/rails_db_inspector)
[![Gem Downloads](https://img.shields.io/gem/dt/rails_db_inspector)](https://rubygems.org/gems/rails_db_inspector)
[![CI](https://github.com/h0m1c1de/rails_db_inspector/actions/workflows/ci.yml/badge.svg)](https://github.com/h0m1c1de/rails_db_inspector/actions/workflows/ci.yml)

---

## Features

- **Real-time SQL Query Capture** — every query your app executes is logged with SQL text, duration, bind parameters, and timestamps
- **N+1 Query Detection** — automatically identifies repeated query patterns and highlights the worst offenders
- **Query Grouping** — queries are grouped by controller action using Rails marginal annotations
- **EXPLAIN Plans** — run `EXPLAIN` on any captured query to see the execution plan (PostgreSQL JSON format, MySQL tabular)
- **EXPLAIN ANALYZE** — optionally run `EXPLAIN ANALYZE` to get real execution statistics, buffer usage, and timing (opt-in, SELECT only)
- **Plan Analysis** — rich visual rendering of PostgreSQL plans including cost breakdown, row estimate accuracy, index usage analysis, performance hotspots, buffer statistics, and actionable recommendations
- **Interactive Schema / ERD Visualization** — drag-and-drop entity relationship diagram with pan, zoom, search, column expansion, heat-map by row count, missing index warnings, polymorphic detection, and SVG export
- **Dev Widget** — floating button injected into your app's pages in development for quick access to the dashboard
- **Zero Dependencies** — no JavaScript build step, no external CSS frameworks, everything is self-contained

---

## Installation

Add to your Gemfile. It is **strongly recommended** to restrict this to `:development` (and optionally `:test`):

```ruby
group :development do
  gem "rails_db_inspector"
end
```

Then run:

```bash
bundle install
```

---

## Setup

### 1. Mount the Engine

Add the engine route to your `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  # ... your app routes ...

  if Rails.env.development?
    mount RailsDbInspector::Engine, at: "/inspect"
  end
end
```

You can use any mount path — `/inspect`, `/db`, `/rails_db_inspector`, etc.

### 2. Create an Initializer (Optional but Recommended)

Create `config/initializers/rails_db_inspector.rb`:

```ruby
RailsDbInspector.configure do |config|
  # Enable or disable the engine entirely.
  # Default: true
  config.enabled = Rails.env.development?

  # Maximum number of queries to keep in memory.
  # Older queries are trimmed when this limit is exceeded.
  # Default: 2000
  config.max_queries = 2_000

  # Allow EXPLAIN ANALYZE to run on captured queries.
  # This actually executes the query, so it is disabled by default for safety.
  # Only SELECT statements are permitted even when enabled.
  # Default: false
  config.allow_explain_analyze = true

  # Show the floating dev widget on your app's pages in development.
  # The widget provides quick links to the query monitor and schema viewer.
  # Default: true
  config.show_widget = true
end
```

### Configuration Options

| Option                  | Type    | Default  | Description                                                                 |
|-------------------------|---------|----------|-----------------------------------------------------------------------------|
| `enabled`               | Boolean | `true`   | Master switch — disables SQL subscription and widget when `false`           |
| `max_queries`           | Integer | `2000`   | Max queries stored in memory (FIFO eviction)                                |
| `allow_explain_analyze` | Boolean | `false`  | Permit EXPLAIN ANALYZE (executes the query — SELECT only)                   |
| `show_widget`           | Boolean | `true`   | Inject floating widget into HTML pages in development                       |

---

## Usage

### Accessing the Dashboard

Once mounted, visit the engine in your browser:

```
http://localhost:3000/inspect
```

(Replace `/inspect` with whatever mount path you chose.)

### Query Monitor

The root page shows all captured SQL queries in reverse-chronological order.

- **Grouped by Controller Action** — queries are automatically grouped using Rails' marginal SQL comments (`controller='...'`, `action='...'`). Enable annotations in your app with:

  ```ruby
  # config/application.rb or config/environments/development.rb
  config.active_record.query_log_tags_enabled = true
  config.active_record.query_log_tags = [
    { controller: ->(context) { context[:controller]&.controller_name } },
    { action:     ->(context) { context[:controller]&.action_name } }
  ]
  ```

- **N+1 Detection** — the dashboard flags queries that appear 3+ times with the same normalized SQL pattern, showing the count, total duration, and table name
- **Query Type Badges** — each query is tagged with its operation (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CTE`) and complexity hints (`JOIN`, `SUBQUERY`, `AGGREGATE`, `ORDER BY`, `WINDOW`)
- **Clear Queries** — use the "Clear" button to reset the in-memory query store

### Running EXPLAIN

Click on any query to view its details, then click **Explain** to get the execution plan.

- **EXPLAIN** — shows the planned execution without running the query (always available)
- **EXPLAIN ANALYZE** — shows actual execution statistics (requires `allow_explain_analyze = true` in the initializer)

For PostgreSQL, the plan is rendered with:
- Visual tree of plan nodes with cost, rows, and width
- Timing and buffer statistics (ANALYZE mode)
- Row estimate accuracy indicators (color-coded)
- Warning badges for sequential scans, large sorts, nested loops, etc.
- Index usage analysis
- Performance hotspot identification
- Cache hit ratio
- Actionable recommendations (e.g., "Create index on `orders.status`")

> **⚠️ Safety:** EXPLAIN ANALYZE actually executes the query. Only `SELECT` statements are allowed — `INSERT`, `UPDATE`, and `DELETE` queries are blocked even when analyze is enabled.

### Schema Visualization

Navigate to the **Schema** page to see an interactive entity relationship diagram:

- **Drag & drop** nodes to rearrange
- **Pan & zoom** with mouse wheel or controls
- **Search** tables with `/` keyboard shortcut
- **Click** a table to see columns, types, indexes, foreign keys, associations, and row count in the detail panel
- **Double-click** a node to expand/collapse its columns
- **Relationships** drawn from foreign keys (solid blue lines) and Rails conventions (dashed gray lines)
- **Heat map** — node headers are color-coded by row count (green → red)
- **Missing index warnings** — yellow badge on tables with `_id` columns lacking an index
- **Polymorphic detection** — purple "P" badge on tables with matching `_type`/`_id` column pairs
- **Health summary** — table count, column count, index count, total rows, missing indexes, tables without timestamps, tables without primary keys, polymorphic columns
- **Export SVG** — download the diagram as an SVG file

### Dev Widget

In development, a floating blue button (🛢️) appears in the bottom-right corner of every page. Click it to reveal quick links to:

- **Query Monitor** — opens the query dashboard
- **Schema Visualization** — opens the ERD viewer

The widget is automatically injected via Rack middleware and only appears in `development` environment. Disable it with `config.show_widget = false`.

---

## Supported Databases

| Adapter    | EXPLAIN | EXPLAIN ANALYZE | Schema / ERD |
|------------|---------|-----------------|--------------|
| PostgreSQL | ✅      | ✅               | ✅            |
| MySQL      | ✅      | ✅               | ✅            |
| SQLite     | ❌      | ❌               | ✅            |

EXPLAIN uses `FORMAT JSON` for PostgreSQL and standard `EXPLAIN` for MySQL.

---

## How It Works

1. **SQL Subscriber** — uses `ActiveSupport::Notifications.subscribe("sql.active_record")` to capture every query. Schema, transaction, cached, and EXPLAIN queries are automatically filtered out.
2. **Query Store** — an in-memory singleton (`QueryStore`) stores captured queries with thread-safe access. Oldest queries are evicted when `max_queries` is exceeded.
3. **Explain** — wraps the captured SQL in an `EXPLAIN` statement appropriate for the database adapter and parses the result.
4. **Schema Inspector** — introspects `ActiveRecord::Base.connection` for tables, columns, indexes, foreign keys, primary keys, row counts, associations, polymorphic columns, and missing indexes.
5. **Dev Widget Middleware** — a Rack middleware that injects a small HTML snippet before `</body>` on HTML responses in development.

---

## Development / Contributing

```bash
# Clone the repo
git clone https://github.com/h0m1c1de/rails_db_inspector.git
cd rails_db_inspector

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bin/rubocop
```

### Running Tests

The test suite uses RSpec with SimpleCov for coverage:

```bash
bundle exec rspec
```

Coverage targets: **95% line**, **85% branch**.

---

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
