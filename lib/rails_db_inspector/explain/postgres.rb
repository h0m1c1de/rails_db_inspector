# frozen_string_literal: true

require "json"

module RailsDbInspector
  class Explain
    class Postgres
      def initialize(connection)
        @connection = connection
      end

      def explain(sql, analyze: false)
        # Strip any existing EXPLAIN prefix to prevent doubling
        clean_sql = sql.sub(/\A\s*EXPLAIN\s*(\([^)]*\))?\s*/i, "")

        statement =
          if analyze
            RailsDbInspector::Explain.select_only!(clean_sql)
            "EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON) #{clean_sql}"
          else
            "EXPLAIN (FORMAT JSON) #{clean_sql}"
          end

        result = @connection.exec_query(statement)
        raw = result.rows.dig(0, 0)
        plan = raw.is_a?(String) ? JSON.parse(raw) : raw

        { adapter: "postgres", analyze: analyze, plan: plan }
      end
    end
  end
end
