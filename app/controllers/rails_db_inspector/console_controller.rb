# frozen_string_literal: true

module RailsDbInspector
  class ConsoleController < ApplicationController
    DANGEROUS_KEYWORDS = /\b(DROP|TRUNCATE|ALTER|CREATE|GRANT|REVOKE)\b/i

    def index
      connection = ActiveRecord::Base.connection
      @tables = connection.tables.reject { |t| t.match?(/^(schema_migrations|ar_internal_metadata)$/) }.sort
      @adapter = connection.adapter_name.downcase
      @allow_writes = RailsDbInspector.configuration.allow_console_writes
    end

    def execute
      sql = params[:sql].to_s.strip
      return render json: { error: "SQL query is required" }, status: :bad_request if sql.blank?

      # Block destructive DDL regardless of config
      if sql.match?(DANGEROUS_KEYWORDS)
        return render json: { error: "Destructive DDL statements (DROP, TRUNCATE, ALTER, CREATE, GRANT, REVOKE) are not allowed." }, status: :forbidden
      end

      # Block writes unless explicitly enabled
      unless RailsDbInspector.configuration.allow_console_writes
        unless sql.match?(/\A\s*(SELECT|EXPLAIN|ANALYZE|PRAGMA|SHOW|DESCRIBE|DESC|\\.d|WITH)\b/i)
          return render json: { error: "Write queries are disabled. Enable with: RailsDbInspector.configuration.allow_console_writes = true" }, status: :forbidden
        end
      end

      connection = ActiveRecord::Base.connection
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        result = connection.exec_query(sql)
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        render json: {
          columns: result.columns,
          rows: result.rows,
          row_count: result.rows.length,
          duration_ms: elapsed
        }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
