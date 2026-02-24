# frozen_string_literal: true

module RailsDbInspector
  class Explain
    class Sqlite
      def initialize(connection)
        @connection = connection
      end

      def explain(sql, analyze: false)
        # Strip any existing EXPLAIN prefix to prevent doubling
        clean_sql = sql.sub(/\A\s*EXPLAIN\s*(QUERY\s+PLAN)?\s*/i, "")

        statement =
          if analyze
            RailsDbInspector::Explain.select_only!(clean_sql)
            "EXPLAIN QUERY PLAN #{clean_sql}"
          else
            "EXPLAIN QUERY PLAN #{clean_sql}"
          end

        result = @connection.exec_query(statement)

        plan = result.rows.map do |row|
          {
            "id" => row[0],
            "parent" => row[1],
            "notused" => row[2],
            "detail" => row[3]
          }
        end

        # Collect cardinality estimates for referenced tables
        table_stats = collect_table_stats(plan)

        { adapter: "sqlite", analyze: analyze, columns: result.columns, rows: result.rows, plan: plan, table_stats: table_stats }
      end

      private

      def collect_table_stats(plan)
        stats = {}
        plan.each do |node|
          detail = node["detail"].to_s
          # Extract table name from patterns like:
          #   SCAN TABLE users
          #   SEARCH TABLE users USING INDEX ...
          #   SCAN users VIRTUAL TABLE ...
          table_match = detail.match(/(?:SCAN|SEARCH)\s+TABLE\s+(\w+)/i)
          next unless table_match

          table_name = table_match[1]
          next if stats.key?(table_name)

          begin
            quoted = @connection.quote_table_name(table_name)
            row_count = @connection.select_value("SELECT COUNT(*) FROM #{quoted}").to_i
            stats[table_name] = {
              row_count: row_count,
              uses_index: detail.match?(/USING.*INDEX/i),
              scan_type: detail.match?(/SCAN TABLE/i) ? "full_scan" : "index_search"
            }
          rescue StandardError
            # Table may not exist or be inaccessible
            stats[table_name] = { row_count: nil, uses_index: false, scan_type: "unknown" }
          end
        end
        stats
      end
    end
  end
end
