# frozen_string_literal: true

module RailsDbInspector
  class SchemaController < ApplicationController
    include RailsDbInspector::ApplicationHelper

    def index
      inspector = RailsDbInspector::SchemaInspector.new
      @schema = inspector.introspect
      @relationships = inspector.relationships
      @table_sizes = inspector.table_sizes
    end

    def analyze_table
      table = params[:table].to_s.gsub(/[^a-zA-Z0-9_]/, "")
      return render json: { error: "Table name required" }, status: :bad_request if table.blank?

      connection = ActiveRecord::Base.connection
      adapter = connection.adapter_name.downcase

      begin
        case adapter
        when /postgres/
          connection.execute("ANALYZE #{connection.quote_table_name(table)}")
        when /mysql/
          connection.execute("ANALYZE TABLE #{connection.quote_table_name(table)}")
        when /sqlite/
          connection.execute("ANALYZE #{connection.quote_table_name(table)}")
        else
          return render json: { error: "ANALYZE not supported for #{adapter}" }, status: :unprocessable_entity
        end

        render json: { success: true, table: table, adapter: adapter, message: "Statistics refreshed for '#{table}'" }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
