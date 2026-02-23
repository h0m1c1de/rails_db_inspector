# frozen_string_literal: true

module RailsDbInspector
  class Explain
    class MySql
      def initialize(connection)
        @connection = connection
      end

      def explain(sql, analyze: false)
        # Strip any existing EXPLAIN prefix to prevent doubling
        clean_sql = sql.sub(/\A\s*EXPLAIN\s*(ANALYZE)?\s*/i, "")

        statement =
          if analyze
            RailsDbInspector::Explain.select_only!(clean_sql)
            "EXPLAIN ANALYZE #{clean_sql}"
          else
            "EXPLAIN #{clean_sql}"
          end

        result = @connection.exec_query(statement)

        { adapter: "mysql", analyze: analyze, columns: result.columns, rows: result.rows }
      end
    end
  end
end
