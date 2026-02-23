# frozen_string_literal: true

module RailsDbInspector
  class SchemaInspector
    attr_reader :connection

    def initialize(connection = ActiveRecord::Base.connection)
      @connection = connection
    end

    IGNORED_TABLES = %w[schema_migrations ar_internal_metadata].freeze

    # Returns a hash of table_name => { columns:, indexes:, foreign_keys: }
    def introspect
      tables = connection.tables.sort - IGNORED_TABLES
      schema = {}

      tables.each do |table|
        columns = introspect_columns(table)
        indexes = introspect_indexes(table)
        schema[table] = {
          columns: columns,
          indexes: indexes,
          foreign_keys: introspect_foreign_keys(table),
          primary_key: introspect_primary_key(table),
          row_count: safe_row_count(table),
          associations: introspect_associations(table),
          missing_indexes: detect_missing_indexes(columns, indexes),
          polymorphic_columns: detect_polymorphic_columns(columns)
        }
      end

      schema
    end

    # Returns relationships between tables for visualization
    def relationships
      rels = []

      (connection.tables.sort - IGNORED_TABLES).each do |table|
        # Foreign key-based relationships
        if connection.respond_to?(:foreign_keys)
          connection.foreign_keys(table).each do |fk|
            rels << {
              from_table: table,
              from_column: fk.column,
              to_table: fk.to_table,
              to_column: fk.primary_key || "id",
              type: :foreign_key
            }
          end
        end

        # Convention-based relationships (belongs_to via _id columns)
        connection.columns(table).each do |col|
          next unless col.name.end_with?("_id")

          referenced_table = col.name.sub(/_id\z/, "").pluralize
          next unless connection.tables.include?(referenced_table)

          # Skip if already covered by a foreign key
          already_covered = rels.any? do |r|
            r[:from_table] == table && r[:from_column] == col.name
          end
          next if already_covered

          rels << {
            from_table: table,
            from_column: col.name,
            to_table: referenced_table,
            to_column: "id",
            type: :convention
          }
        end
      end

      rels
    end

    private

    def introspect_columns(table)
      connection.columns(table).map do |col|
        {
          name: col.name,
          type: col.sql_type,
          nullable: col.null,
          default: col.default
        }
      end
    end

    def introspect_indexes(table)
      connection.indexes(table).map do |idx|
        {
          name: idx.name,
          columns: idx.columns,
          unique: idx.unique
        }
      end
    end

    def introspect_foreign_keys(table)
      return [] unless connection.respond_to?(:foreign_keys)

      connection.foreign_keys(table).map do |fk|
        {
          column: fk.column,
          to_table: fk.to_table,
          primary_key: fk.primary_key || "id",
          name: fk.name
        }
      end
    end

    def introspect_primary_key(table)
      connection.primary_key(table)
    end

    def safe_row_count(table)
      quoted = connection.quote_table_name(table)
      result = connection.select_value("SELECT COUNT(*) FROM #{quoted}")
      result.to_i
    rescue StandardError
      nil
    end

    def introspect_associations(table)
      model = find_model_for_table(table)
      return [] unless model

      model.reflect_on_all_associations.map do |assoc|
        target_table = begin
          assoc.klass.table_name
        rescue StandardError
          nil
        end

        {
          name: assoc.name.to_s,
          macro: assoc.macro.to_s,
          target_table: target_table,
          foreign_key: assoc.foreign_key.to_s,
          through: assoc.options[:through]&.to_s
        }
      end
    rescue StandardError
      []
    end

    # Detect _id columns that lack a corresponding index
    def detect_missing_indexes(columns, indexes)
      indexed_columns = indexes.flat_map { |idx| idx[:columns] }.to_set

      columns
        .select { |col| col[:name].end_with?("_id") }
        .reject { |col| indexed_columns.include?(col[:name]) }
        .map { |col| col[:name] }
    end

    # Detect polymorphic column pairs (*_type + *_id)
    def detect_polymorphic_columns(columns)
      col_names = columns.map { |c| c[:name] }.to_set
      polymorphics = []

      columns.each do |col|
        next unless col[:name].end_with?("_type")

        base = col[:name].sub(/_type\z/, "")
        id_col = "#{base}_id"
        next unless col_names.include?(id_col)

        polymorphics << {
          name: base,
          type_column: col[:name],
          id_column: id_col
        }
      end

      polymorphics
    end

    def find_model_for_table(table)
      # Force-load all models so descendants are populated
      eager_load_models!

      ActiveRecord::Base.descendants.detect do |klass|
        klass.table_name == table && !klass.abstract_class?
      rescue StandardError
        false
      end
    rescue StandardError
      nil
    end

    def eager_load_models!
      return if @models_loaded
      @models_loaded = true

      # Use Zeitwerk autoloader to load all models
      model_paths = Rails.application.config.paths["app/models"].to_a
      model_paths.each do |dir|
        Dir.glob("#{dir}/**/*.rb").sort.each do |file|
          begin
            require file
          rescue StandardError, LoadError
            # Skip models that fail to load
          end
        end
      end

      # Fallback: eager load the whole app if no descendants found
      if ActiveRecord::Base.descendants.reject { |k| k.abstract_class? rescue true }.empty?
        begin
          Rails.application.eager_load!
        rescue StandardError
          # ignore
        end
      end
    end
  end
end
