# frozen_string_literal: true

module RailsDbInspector
  class Explain
    class UnsupportedAdapter < StandardError; end
    class DangerousQuery < StandardError; end

    def self.for_connection(connection)
      adapter = connection.adapter_name.to_s.downcase

      case adapter
      when /postgres/
        RailsDbInspector::Explain::Postgres.new(connection)
      when /mysql/
        RailsDbInspector::Explain::MySql.new(connection)
      when /sqlite/
        RailsDbInspector::Explain::Sqlite.new(connection)
      else
        raise UnsupportedAdapter, "Unsupported adapter: #{connection.adapter_name}"
      end
    end

    def self.select_only!(sql)
      return if sql.strip.match?(/\ASELECT\b/i)

      raise DangerousQuery, "Only SELECT is allowed for EXPLAIN ANALYZE by default"
    end
  end
end
