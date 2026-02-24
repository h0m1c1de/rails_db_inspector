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

        { adapter: "sqlite", analyze: analyze, columns: result.columns, rows: result.rows, plan: plan }
      end
    end
  end
end
