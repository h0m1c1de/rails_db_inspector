# frozen_string_literal: true

require "singleton"
require "securerandom"
require "thread"

module RailsDbInspector
  class QueryStore
    include Singleton

    Query = Struct.new(
      :id,
      :sql,
      :name,
      :binds,
      :duration_ms,
      :connection_id,
      :timestamp,
      keyword_init: true
    )

    def initialize
      @mutex = Mutex.new
      @queries = []
      @by_id = {}
    end

    def add(sql:, name:, binds:, duration_ms:, connection_id:, timestamp:)
      q = Query.new(
        id: SecureRandom.hex(8),
        sql: sql,
        name: name,
        binds: normalize_binds(binds),
        duration_ms: duration_ms.to_f,
        connection_id: connection_id,
        timestamp: timestamp
      )

      @mutex.synchronize do
        @queries << q
        @by_id[q.id] = q
        trim!
      end

      q
    end

    def all
      @mutex.synchronize { @queries.dup }
    end

    def find(id)
      @mutex.synchronize { @by_id[id] }
    end

    def clear!
      @mutex.synchronize do
        @queries.clear
        @by_id.clear
      end
    end

    private

    def trim!
      max = RailsDbInspector.configuration.max_queries.to_i
      return if max <= 0
      return if @queries.length <= max

      drop_count = @queries.length - max
      dropped = @queries.shift(drop_count)
      dropped.each { |q| @by_id.delete(q.id) }
    end

    def normalize_binds(binds)
      return [] unless binds.is_a?(Array)

      binds.map do |b|
        if b.respond_to?(:name) && b.respond_to?(:value_before_type_cast)
          { name: b.name, value: b.value_before_type_cast, type: b.type&.type }
        elsif b.is_a?(Array) && b.length == 2
          { name: b[0].to_s, value: b[1], type: nil }
        else
          { name: nil, value: b.to_s, type: nil }
        end
      end
    end
  end
end
