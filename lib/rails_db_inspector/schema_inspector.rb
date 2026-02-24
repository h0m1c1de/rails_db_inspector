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
        polymorphic_columns = detect_polymorphic_columns(columns)
        associations = introspect_associations(table)

        schema[table] = {
          columns: columns,
          indexes: indexes,
          foreign_keys: introspect_foreign_keys(table),
          primary_key: introspect_primary_key(table),
          row_count: safe_row_count(table),
          associations: associations,
          missing_indexes: detect_missing_indexes(columns, indexes),
          polymorphic_columns: polymorphic_columns,
          index_suggestions: detect_index_suggestions(table, columns, indexes, polymorphic_columns, associations)
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

    # Build a unified list of index suggestions from multiple strategies
    def detect_index_suggestions(table, columns, indexes, polymorphic_columns, associations)
      suggestions = []
      suggestions.concat(suggest_polymorphic_composite_indexes(table, indexes, polymorphic_columns))
      suggestions.concat(suggest_join_table_composite_indexes(table, columns, indexes, associations))
      suggestions.concat(suggest_query_driven_indexes(table, indexes))
      suggestions.uniq { |s| s[:columns].sort }
    end

    # Strategy 1: Composite indexes for polymorphic associations [type, id]
    def suggest_polymorphic_composite_indexes(table, indexes, polymorphic_columns)
      return [] if polymorphic_columns.empty?

      existing_composites = indexes
        .select { |idx| idx[:columns].length >= 2 }
        .map { |idx| idx[:columns].map(&:to_s) }

      polymorphic_columns.filter_map do |poly|
        cols = [ poly[:type_column], poly[:id_column] ]

        # Skip if a composite index already covers these columns (in any order)
        next if existing_composites.any? { |ec| (cols - ec).empty? }

        {
          columns: cols,
          reason: :polymorphic,
          message: "Composite index recommended for polymorphic association '#{poly[:name]}'. " \
                   "Queries on polymorphic associations filter by both type and id.",
          sql: "CREATE INDEX index_#{table}_on_#{poly[:name]} ON #{table} (#{cols.join(', ')});",
          migration: "add_index :#{table}, [:#{cols.join(', :')}]"
        }
      end
    end

    # Strategy 2: Composite indexes for join tables (has_many :through)
    def suggest_join_table_composite_indexes(table, columns, indexes, associations)
      # A join table typically has two or more _id columns
      id_columns = columns.select { |c| c[:name].end_with?("_id") }.map { |c| c[:name] }
      return [] unless id_columns.length >= 2

      # Check if this table is used as a :through join table by any association
      is_join_table = associations.any? { |a| a[:through].to_s == table } ||
                      looks_like_join_table?(table, columns)

      return [] unless is_join_table

      existing_composites = indexes
        .select { |idx| idx[:columns].length >= 2 }
        .map { |idx| idx[:columns].map(&:to_s) }

      suggestions = []

      # Suggest composite index on the pair of FK columns
      fk_pairs = id_columns.combination(2).to_a
      fk_pairs.each do |pair|
        next if existing_composites.any? { |ec| (pair - ec).empty? }

        suggestions << {
          columns: pair,
          reason: :join_table,
          message: "Composite index recommended for join table '#{table}'. " \
                   "Queries through this table typically filter on both foreign keys.",
          sql: "CREATE INDEX index_#{table}_on_#{pair.join('_and_')} ON #{table} (#{pair.join(', ')});",
          migration: "add_index :#{table}, [:#{pair.join(', :')}]"
        }

        # Also suggest a unique composite if not already present
        has_unique = indexes.any? { |idx| idx[:unique] && (pair - idx[:columns].map(&:to_s)).empty? }
        unless has_unique
          suggestions << {
            columns: pair,
            reason: :join_table_unique,
            message: "Consider a unique composite index on '#{table}' to prevent duplicate associations.",
            sql: "CREATE UNIQUE INDEX index_#{table}_on_#{pair.join('_and_')}_unique ON #{table} (#{pair.join(', ')});",
            migration: "add_index :#{table}, [:#{pair.join(', :')}], unique: true"
          }
        end
      end

      suggestions
    end

    # Strategy 3: Query-driven index suggestions from captured queries
    def suggest_query_driven_indexes(table, indexes)
      queries = RailsDbInspector::QueryStore.instance.all
      return [] if queries.empty?

      existing_indexed = indexes.flat_map { |idx| idx[:columns].map(&:to_s) }.to_set
      existing_composites = indexes
        .select { |idx| idx[:columns].length >= 2 }
        .map { |idx| idx[:columns].map(&:to_s) }

      column_usage = Hash.new(0)
      composite_candidates = Hash.new(0)

      queries.each do |query|
        sql = query.sql.to_s
        next unless references_table?(sql, table)

        where_columns = extract_where_columns(sql, table)
        order_columns = extract_order_columns(sql, table)

        # Track individual column usage
        (where_columns + order_columns).each { |col| column_usage[col] += 1 }

        # Track composite patterns (WHERE + ORDER BY or multi-column WHERE)
        combined = (where_columns + order_columns).uniq
        if combined.length >= 2
          composite_candidates[combined.sort] += 1
        end
      end

      suggestions = []

      # Suggest composite indexes for frequently co-occurring columns
      composite_candidates
        .select { |_cols, count| count >= 2 }
        .sort_by { |_cols, count| -count }
        .first(5)
        .each do |cols, count|
          next if existing_composites.any? { |ec| (cols - ec).empty? }
          next if cols.any? { |c| c.include?("*") || c.include?("(") } # skip bad parses

          suggestions << {
            columns: cols,
            reason: :query_pattern,
            message: "Composite index suggested based on #{count} captured queries " \
                     "that filter/sort on these columns together.",
            sql: "CREATE INDEX index_#{table}_on_#{cols.join('_and_')} ON #{table} (#{cols.join(', ')});",
            migration: "add_index :#{table}, [:#{cols.join(', :')}]"
          }
        end

      suggestions
    end

    # Check if a table name appears in a SQL statement
    def references_table?(sql, table)
      sql.match?(/\b#{Regexp.escape(table)}\b/i)
    end

    # Extract column names from WHERE clauses referencing a table
    def extract_where_columns(sql, table)
      columns = []

      # Only proceed if there's actually a WHERE clause
      parts = sql.split(/\bWHERE\b/i, 2)
      return columns if parts.length < 2

      where_section = parts.last.to_s
      where_section = where_section.split(/\b(?:ORDER|GROUP|HAVING|LIMIT|UNION)\b/i, 2).first.to_s

      # table.column or "table"."column" patterns
      where_section.scan(/(?:#{Regexp.escape(table)}|"#{Regexp.escape(table)}")\.(?:"?(\w+)"?)/i) do |match|
        columns << match[0]
      end

      # Simple column = ? patterns (only if single table query)
      if sql.scan(/\b(?:FROM|JOIN)\b/i).length <= 1
        where_section.scan(/\b(\w+)\s*(?:=|!=|<>|>=?|<=?|IN|IS|LIKE|BETWEEN|@@)\s/i) do |match|
          col = match[0]
          next if sql_keyword?(col)
          next if col.match?(/\A\d+\z/) # skip numeric literals
          columns << col
        end
      end

      columns.uniq
    end

    # Extract column names from ORDER BY clauses
    def extract_order_columns(sql, table)
      columns = []

      # Only proceed if there's actually an ORDER BY clause
      parts = sql.split(/\bORDER\s+BY\b/i, 2)
      return columns if parts.length < 2

      order_section = parts.last.to_s
      order_section = order_section.split(/\b(?:LIMIT|OFFSET|UNION|HAVING)\b/i, 2).first.to_s

      order_section.scan(/(?:#{Regexp.escape(table)}|"#{Regexp.escape(table)}")\.(?:"?(\w+)"?)/i) do |match|
        columns << match[0]
      end

      if sql.scan(/\b(?:FROM|JOIN)\b/i).length <= 1
        order_section.scan(/\b(\w+)\b/) do |match|
          col = match[0]
          next if sql_keyword?(col)
          columns << col
        end
      end

      columns.uniq
    end

    SQL_KEYWORDS = %w[
      AND OR NOT NULL TRUE FALSE SELECT FROM WHERE JOIN ON IN IS LIKE BETWEEN
      AS BY ASC DESC NULLS FIRST LAST GROUP ORDER HAVING LIMIT OFFSET UNION
      INSERT UPDATE DELETE SET VALUES INTO TABLE CREATE INDEX DISTINCT COUNT
      SUM AVG MIN MAX CASE WHEN THEN ELSE END EXISTS ALL ANY INNER OUTER
      LEFT RIGHT CROSS FULL NATURAL USING WITH RECURSIVE
    ].to_set.freeze

    def sql_keyword?(word)
      SQL_KEYWORDS.include?(word.upcase)
    end

    # Heuristic: does this table look like a join table?
    def looks_like_join_table?(table, columns)
      col_names = columns.map { |c| c[:name] }
      id_cols = col_names.select { |n| n.end_with?("_id") }

      # Join tables typically have 2+ FK columns and few other columns
      non_meta = col_names - %w[id created_at updated_at] - id_cols
      id_cols.length >= 2 && non_meta.length <= 2
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
