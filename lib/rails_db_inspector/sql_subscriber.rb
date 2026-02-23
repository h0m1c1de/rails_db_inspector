# frozen_string_literal: true

module RailsDbInspector
  class SqlSubscriber
    IGNORED_NAMES = [
      "SCHEMA",
      "TRANSACTION",
      "ActiveRecord::SchemaMigration Load",
      "ActiveRecord::InternalMetadata Load"
    ].freeze

    def self.install!
      return if @installed

      @installed = true
      RailsDbInspector::QueryStore.instance

      ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        payload = event.payload

        name = payload[:name].to_s
        sql  = payload[:sql].to_s

        next if sql.strip.empty?
        next if IGNORED_NAMES.include?(name)
        next if sql =~ /\A(?:BEGIN|COMMIT|ROLLBACK)\b/i
        next if sql =~ /\A\s*EXPLAIN\b/i
        next if payload[:cached]

        RailsDbInspector::QueryStore.instance.add(
          sql: sql,
          name: name,
          binds: payload[:binds],
          duration_ms: event.duration,
          connection_id: payload[:connection_id],
          timestamp: (event.time.is_a?(Time) ? event.time : Time.at(event.time.to_f))
        )
      end
    end
  end
end
