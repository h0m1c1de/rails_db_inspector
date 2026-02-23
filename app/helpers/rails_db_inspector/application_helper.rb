require_relative "plan_renderer"

module RailsDbInspector
  module ApplicationHelper
    def render_postgres_plan(plan_data)
      renderer = RailsDbInspector::ApplicationHelper::PostgresPlanRenderer.new(plan_data)
      (renderer.render_summary + renderer.render_tree).html_safe
    end

    def render_query_type(query)
      sql = query.sql.downcase.strip

      # Determine the primary operation
      operation = case sql
      when /^select\b/
        "SELECT"
      when /^insert\b/
        "INSERT"
      when /^update\b/
        "UPDATE"
      when /^delete\b/
        "DELETE"
      when /^with\b/
        "CTE"
      else
        "OTHER"
      end

      # Add complexity indicators for SELECT queries
      complexity_hints = []

      if operation == "SELECT"
        complexity_hints << "JOIN" if sql.include?(" join ")
        complexity_hints << "SUBQUERY" if sql.include?("(select") || sql.include?("( select")
        complexity_hints << "AGGREGATE" if sql.match?(/\b(count|sum|avg|max|min|group by)\b/)
        complexity_hints << "ORDER BY" if sql.include?(" order by ")
        complexity_hints << "WINDOW" if sql.include?(" over(") || sql.include?(" over (")
      end

      # Render the operation with complexity hints
      result_html = "<span class=\"inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-gray-100 text-gray-800\">#{operation}</span>"

      complexity_hints.each do |hint|
        case hint
        when "JOIN"
          result_html += " <span class=\"inline-flex items-center px-1.5 py-0.5 rounded text-xs bg-blue-100 text-blue-800\">#{hint}</span>"
        when "AGGREGATE", "WINDOW"
          result_html += " <span class=\"inline-flex items-center px-1.5 py-0.5 rounded text-xs bg-yellow-100 text-yellow-800\">#{hint}</span>"
        when "SUBQUERY"
          result_html += " <span class=\"inline-flex items-center px-1.5 py-0.5 rounded text-xs bg-red-100 text-red-800\">#{hint}</span>"
        else
          result_html += " <span class=\"inline-flex items-center px-1.5 py-0.5 rounded text-xs bg-green-100 text-green-800\">#{hint}</span>"
        end
      end

      result_html.html_safe
    end

    def group_queries_by_action(queries)
      return [] if queries.empty?

      groups = []
      current_group = nil

      queries.each do |query|
        controller_action = extract_controller_action_from_sql(query)

        # Start a new group if:
        # 1. No current group
        # 2. Different controller/action
        # 3. Time gap of more than 10 seconds from the last query in the group
        if current_group.nil? ||
           current_group[:action] != controller_action ||
           time_gap_too_large?(query, current_group[:queries].last, 10.0)

          current_group = {
            action: controller_action,
            queries: [],
            start_time: query.timestamp,
            request_type: determine_request_type_from_action(controller_action)
          }
          groups << current_group
        end

        current_group[:queries] << query
      end

      groups
    end

    def detect_n_plus_one(queries)
      return [] if queries.length < 3

      # Normalize queries by replacing literal values with placeholders
      normalized = queries.map do |q|
        {
          query: q,
          normalized: normalize_sql(q.sql)
        }
      end

      # Group by normalized SQL
      groups = normalized.group_by { |entry| entry[:normalized] }

      # Find N+1 patterns: same normalized query appearing 3+ times
      n_plus_ones = []
      groups.each do |normalized_sql, entries|
        next if entries.length < 3
        next if normalized_sql.strip.empty?

        # Skip schema/transaction queries
        next if normalized_sql =~ /\A(BEGIN|COMMIT|ROLLBACK|SET|SHOW)\b/i

        sample_query = entries.first[:query]
        total_duration = entries.sum { |e| e[:query].duration_ms }

        # Try to extract the table name
        table = normalized_sql.match(/FROM\s+"?(\w+)"?/i)&.captures&.first || "unknown"

        n_plus_ones << {
          normalized_sql: normalized_sql,
          count: entries.length,
          queries: entries.map { |e| e[:query] },
          sample: sample_query,
          total_duration_ms: total_duration,
          table: table,
          name: sample_query.name
        }
      end

      # Sort by count descending (worst offenders first)
      n_plus_ones.sort_by { |n| -n[:count] }
    end

    private

    def normalize_sql(sql)
      normalized = sql.dup
      # Remove SQL comments like /*...*/ (Rails marginal annotations)
      normalized.gsub!(/\/\*.*?\*\//m, "")
      # Replace string literals 'value' with ?
      normalized.gsub!(/'[^']*'/, "?")
      # Replace numeric literals (integers and floats)
      normalized.gsub!(/\b\d+(\.\d+)?\b/, "?")
      # Replace $1, $2 style bind params
      normalized.gsub!(/\$\d+/, "?")
      # Collapse whitespace
      normalized.gsub!(/\s+/, " ")
      normalized.strip
    end

    def extract_controller_action_from_sql(query)
      sql = query.sql.to_s

      # Look for controller and action in SQL comments
      if match = sql.match(/\/\*.*?controller='([^']+)'.*?action='([^']+)'.*?\*\//)
        controller = match[1]
        action = match[2]

        # Handle namespaced controllers properly
        if controller.include?("/")
          # Convert api/users to Api::UsersController
          controller_parts = controller.split("/")
          namespaced_controller = controller_parts.map(&:camelize).join("::") + "Controller"
        else
          namespaced_controller = "#{controller.camelize}Controller"
        end

        return "#{namespaced_controller}##{action}"
      end

      # Fallback to query name if no controller/action found
      query.name.to_s.presence || "Unknown Query"
    end

    def determine_request_type_from_action(action_name)
      case action_name
      when /API::|Api::|\/api\//i
        :api
      when /Controller#/
        # Check if it looks like an API endpoint based on common patterns
        if action_name.match(/(show|index|create|update|destroy)/) &&
           !action_name.match(/(new|edit)/)
          # Could be API if no render actions (new/edit are typically web-only)
          :web_or_api
        else
          :web_request
        end
      when /Load|Create|Update|Delete|Destroy/
        :model_operation
      when /Schema|Migration/i
        :schema
      else
        :other
      end
    end

    def group_icon(request_type)
      case request_type
      when :api
        "🔗"
      when :web_request
        "🌐"
      when :web_or_api
        "🔀"  # Mixed/ambiguous
      when :model_operation
        "📊"
      when :schema
        "🗂️"
      else
        "💾"
      end
    end

    def time_gap_too_large?(current_query, last_query, gap_seconds = 5.0)
      return false if last_query.nil?

      current_time = parse_timestamp(current_query.timestamp)
      last_time = parse_timestamp(last_query.timestamp)

      (current_time - last_time).abs > gap_seconds
    end

    def parse_timestamp(timestamp)
      case timestamp
      when Time
        timestamp
      when Numeric
        Time.at(timestamp)
      else
        Time.parse(timestamp.to_s)
      end
    rescue
      Time.now
    end

    def format_group_time_range(group)
      return "" if group[:queries].empty?

      start_time = parse_timestamp(group[:start_time])
      end_time = parse_timestamp(group[:queries].last.timestamp)

      if (end_time - start_time) < 1.0
        start_time.strftime("%H:%M:%S")
      else
        "#{start_time.strftime('%H:%M:%S')} - #{end_time.strftime('%H:%M:%S')}"
      end
    end

    # JSON serialization helpers for schema visualization
    def schema_to_json(schema)
      result = {}
      schema.each do |table_name, info|
        result[table_name] = {
          columns: info[:columns].map { |c| { name: c[:name], type: c[:type], nullable: c[:nullable], default: c[:default] } },
          indexes: info[:indexes].map { |i| { name: i[:name], columns: i[:columns], unique: i[:unique] } },
          foreign_keys: info[:foreign_keys].map { |fk| { column: fk[:column], to_table: fk[:to_table], primary_key: fk[:primary_key] } },
          primary_key: info[:primary_key],
          row_count: info[:row_count],
          associations: (info[:associations] || []).map { |a| { name: a[:name], macro: a[:macro], target_table: a[:target_table], foreign_key: a[:foreign_key], through: a[:through] } },
          missing_indexes: info[:missing_indexes] || [],
          polymorphic_columns: (info[:polymorphic_columns] || []).map { |p| { name: p[:name], type_column: p[:type_column], id_column: p[:id_column] } }
        }
      end
      result.to_json
    end

    def relationships_to_json(relationships)
      relationships.map do |r|
        { from_table: r[:from_table], from_column: r[:from_column], to_table: r[:to_table], to_column: r[:to_column], type: r[:type].to_s }
      end.to_json
    end
  end
end
