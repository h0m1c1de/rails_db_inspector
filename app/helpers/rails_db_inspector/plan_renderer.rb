# frozen_string_literal: true

require "securerandom"
require "erb"

module RailsDbInspector
  module ApplicationHelper
    class PostgresPlanRenderer
      def initialize(plan_data)
        @plan_data = plan_data
        @plan = plan_data[:plan]
        @analyze = plan_data[:analyze]
      end

      def render_summary
        return "" unless @plan && @plan.is_a?(Array) && @plan.first

        root_plan = @plan.first
        execution_time = root_plan["Execution Time"]
        planning_time = root_plan["Planning Time"]
        total_cost = root_plan["Plan"]["Total Cost"]
        actual_rows = root_plan["Plan"]["Actual Rows"] if @analyze

        hotspots = find_hotspots(root_plan["Plan"]) if @analyze
        index_analysis = analyze_index_usage(root_plan["Plan"])
        buffer_stats = collect_buffer_stats(root_plan["Plan"]) if @analyze
        recommendations = generate_recommendations(root_plan, index_analysis, buffer_stats)

        summary_html = <<~HTML
          <div class="bg-gray-50 border border-gray-200 rounded-lg p-6 mb-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Execution Summary</h3>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
        HTML

        if execution_time
          summary_html += <<~HTML
            <div class="bg-white p-4 rounded-md border-l-4 border-blue-400">
              <div class="text-xs font-medium text-gray-500 uppercase tracking-wide">Execution Time</div>
              <div class="text-lg font-semibold text-gray-900 font-mono">#{execution_time}ms</div>
              <div class="text-xs text-gray-400 mt-1">Actual wall-clock time to execute the query.</div>
            </div>
          HTML
        end

        if planning_time
          summary_html += <<~HTML
            <div class="bg-white p-4 rounded-md border-l-4 border-green-400">
              <div class="text-xs font-medium text-gray-500 uppercase tracking-wide">Planning Time</div>
              <div class="text-lg font-semibold text-gray-900 font-mono">#{planning_time}ms</div>
              <div class="text-xs text-gray-400 mt-1">Time spent choosing the best execution strategy.</div>
            </div>
          HTML
        end

        if total_cost
          summary_html += <<~HTML
            <div class="bg-white p-4 rounded-md border-l-4 border-purple-400">
              <div class="text-xs font-medium text-gray-500 uppercase tracking-wide">Total Cost</div>
              <div class="text-lg font-semibold text-gray-900 font-mono">#{total_cost}</div>
              <div class="text-xs text-gray-400 mt-1">Arbitrary units representing estimated I/O and CPU work. Lower is better.</div>
            </div>
          HTML
        end

        if actual_rows
          summary_html += <<~HTML
            <div class="bg-white p-4 rounded-md border-l-4 border-yellow-400">
              <div class="text-xs font-medium text-gray-500 uppercase tracking-wide">Rows Returned</div>
              <div class="text-lg font-semibold text-gray-900 font-mono">#{number_with_delimiter(actual_rows)}</div>
              <div class="text-xs text-gray-400 mt-1">Number of rows the query actually produced.</div>
            </div>
          HTML
        end

        # Add index usage summary
        summary_html += <<~HTML
          <div class="bg-white p-4 rounded-md border-l-4 border-indigo-400">
            <div class="text-xs font-medium text-gray-500 uppercase tracking-wide">Index Usage</div>
            <div class="text-lg font-semibold text-gray-900 font-mono">#{index_analysis[:index_scans]} / #{index_analysis[:total_scans]} scans</div>
            <div class="text-xs text-gray-400 mt-1">How many data lookups used an index vs scanning the whole table. Higher is better.</div>
          </div>
        HTML

        # Add cache hit ratio if we have buffer stats
        if buffer_stats && buffer_stats[:total_blocks] > 0
          hit_ratio = ((buffer_stats[:hit_blocks].to_f / buffer_stats[:total_blocks]) * 100).round(1)
          hit_color = hit_ratio >= 99 ? "border-green-400" : (hit_ratio >= 90 ? "border-yellow-400" : "border-red-400")
          summary_html += <<~HTML
            <div class="bg-white p-4 rounded-md border-l-4 #{hit_color}">
              <div class="text-xs font-medium text-gray-500 uppercase tracking-wide">Cache Hit Ratio</div>
              <div class="text-lg font-semibold text-gray-900 font-mono">#{hit_ratio}%</div>
              <div class="text-xs text-gray-400 mt-1">Percentage of data pages found in memory. Below 99% may indicate insufficient shared_buffers.</div>
            </div>
          HTML
        end

        summary_html += "</div>"

        # Index analysis section
        if index_analysis[:warnings].any? || index_analysis[:indexes_used].any?
          summary_html += <<~HTML
            <div class="mt-6">
              <h4 class="text-md font-medium text-gray-900 mb-3">Index Analysis</h4>
          HTML

          if index_analysis[:indexes_used].any?
            summary_html += <<~HTML
              <div class="bg-green-50 border border-green-200 rounded-md p-3 mb-3">
                <div class="flex">
                  <div class="flex-shrink-0">
                    <svg class="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                    </svg>
                  </div>
                  <div class="ml-3">
                    <p class="text-sm font-medium text-green-800">
                      <strong>Indexes Used:</strong> #{ERB::Util.html_escape(index_analysis[:indexes_used].join(", "))}
                    </p>
                  </div>
                </div>
              </div>
            HTML
          end

          if index_analysis[:warnings].any?
            index_analysis[:warnings].each do |warning|
              summary_html += <<~HTML
                <div class="bg-yellow-50 border border-yellow-200 rounded-md p-3 mb-2">
                  <div class="flex">
                    <div class="flex-shrink-0">
                      <svg class="h-5 w-5 text-yellow-400" viewBox="0 0 20 20" fill="currentColor">
                        <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
                      </svg>
                    </div>
                    <div class="ml-3">
                      <p class="text-sm text-yellow-700">#{ERB::Util.html_escape(warning)}</p>
                    </div>
                  </div>
                </div>
              HTML
            end
          end

          summary_html += "</div>"
        end

        if hotspots && hotspots.any?
          summary_html += <<~HTML
            <div class="mt-6">
              <h4 class="text-md font-medium text-gray-900 mb-3">Performance Hotspots</h4>
          HTML

          hotspots.first(3).each do |hotspot|
            summary_html += <<~HTML
              <div class="bg-red-50 border border-red-200 rounded-md p-3 mb-2">
                <p class="text-sm font-mono text-red-700">#{ERB::Util.html_escape(hotspot)}</p>
              </div>
            HTML
          end

          summary_html += "</div>"
        end

        # Recommendations section
        if recommendations.any?
          summary_html += <<~HTML
            <div class="mt-6">
              <h4 class="text-md font-medium text-gray-900 mb-3">💡 Recommendations</h4>
          HTML

          recommendations.each do |rec|
            icon = case rec[:severity]
            when :critical then "🔴"
            when :warning then "🟡"
            when :info then "🔵"
            else "💡"
            end

            border_class = case rec[:severity]
            when :critical then "border-red-300 bg-red-50"
            when :warning then "border-yellow-300 bg-yellow-50"
            when :info then "border-blue-300 bg-blue-50"
            else "border-gray-300 bg-gray-50"
            end

            text_class = case rec[:severity]
            when :critical then "text-red-800"
            when :warning then "text-yellow-800"
            when :info then "text-blue-800"
            else "text-gray-800"
            end

            summary_html += <<~HTML
              <div class="border #{border_class} rounded-md p-4 mb-3">
                <div class="flex items-start">
                  <span class="text-lg mr-3 flex-shrink-0">#{icon}</span>
                  <div class="flex-1">
                    <p class="text-sm font-semibold #{text_class}">#{ERB::Util.html_escape(rec[:title])}</p>
                    <p class="text-sm #{text_class} mt-1">#{ERB::Util.html_escape(rec[:description])}</p>
            HTML

            if rec[:action]
              summary_html += <<~HTML
                    <div class="mt-2 bg-white bg-opacity-60 rounded p-2">
                      <p class="text-xs font-medium text-gray-600">Suggested action:</p>
                      <code class="text-xs font-mono text-gray-800 break-all">#{ERB::Util.html_escape(rec[:action])}</code>
                    </div>
              HTML
            end

            summary_html += <<~HTML
                  </div>
                </div>
              </div>
            HTML
          end

          summary_html += "</div>"
        end

        summary_html += "</div>"
        summary_html
      end

      def render_tree
        return "" unless @plan && @plan.is_a?(Array) && @plan.first

        root_plan = @plan.first["Plan"]
        tree_html = '<div class="font-mono text-sm space-y-2">'
        tree_html += render_node(root_plan, 0)
        tree_html += "</div>"
        tree_html
      end

      private

      def render_node(node, depth)
        node_id = "node_#{SecureRandom.hex(6)}"
        warnings = detect_warnings(node)

        html = <<~HTML
          <div class="border border-gray-200 rounded-lg bg-white shadow-sm">
            <div class="p-3 cursor-pointer select-none relative bg-gray-50 border-b border-gray-200 rounded-t-lg hover:bg-gray-100" onclick="toggleNode('#{node_id}')">
        HTML

        if has_children?(node)
          html += '<button class="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 border-none bg-blue-600 text-white rounded-sm text-xs font-bold cursor-pointer hover:bg-blue-700">−</button>'
        end

        html += '<div class="'
        html += has_children?(node) ? "ml-8" : "ml-3"
        html += ' flex flex-wrap items-center gap-2">'
        html += render_node_title(node, warnings)
        html += "</div></div>"

        html += '<div class="plan-node-body" id="' + node_id + '">'
        html += render_node_details(node)

        if has_children?(node)
          html += '<div class="pl-6 space-y-2">'
          children = node["Plans"] || []
          children.each do |child|
            html += render_node(child, depth + 1)
          end
          html += "</div>"
        end

        html += "</div></div>"
        html
      end

      def render_node_title(node, warnings)
        node_type = node["Node Type"]
        title_html = "<span class=\"font-bold text-gray-700"

        # Add special styling for index operations
        if node_type.include?("Index") || node_type == "Bitmap Index Scan"
          title_html += " text-green-700 bg-green-100 px-2 py-1 rounded"
        elsif node_type == "Seq Scan"
          title_html += " text-red-700 bg-red-100 px-2 py-1 rounded"
        end

        title_html += "\">#{ERB::Util.html_escape(node_type)}</span>"

        # Add relation name
        if node["Relation Name"]
          relation_name = node["Relation Name"]
          relation_name += ".#{node["Schema"]}" if node["Schema"] && node["Schema"] != "public"
          title_html += " <span class=\"text-blue-600 font-semibold\">#{ERB::Util.html_escape(relation_name)}</span>"
        end

        # Add index name with emphasis
        if node["Index Name"]
          title_html += " <span class=\"text-green-700 font-bold bg-green-100 px-2 py-1 rounded inline-flex items-center\">📊 #{ERB::Util.html_escape(node["Index Name"])}</span>"
        end

        # Add timing info for ANALYZE
        if @analyze && node["Actual Total Time"]
          time_class = node["Actual Total Time"] > 100 ? "text-red-600 bg-red-100" : "text-green-600 bg-green-100"
          title_html += " <span class=\"#{time_class} px-2 py-1 rounded font-semibold\">#{node["Actual Total Time"]}ms</span>"
        end

        # Add row count info with better ratio analysis
        if @analyze && node["Actual Rows"] && node["Plan Rows"]
          actual = node["Actual Rows"]
          estimated = node["Plan Rows"]
          abs_diff = (actual - estimated).abs
          ratio = estimated > 0 ? (actual.to_f / estimated).round(2) : (actual == 0 ? 1.0 : "∞")

          # Only flag as problematic when the absolute difference is large enough
          # to actually affect plan choice. Small diffs (e.g. 0 vs 1) are harmless.
          if abs_diff <= 100
            # Small absolute difference — never a real problem
            ratio_class = "text-blue-600 bg-blue-100"
          elsif ratio.is_a?(Numeric)
            if ratio < 0.1 || ratio > 10
              # 10x+ mismatch with >100 row diff — likely a bad plan
              ratio_class = "text-red-600 bg-red-100 font-bold"
            elsif ratio < 0.5 || ratio > 2
              # 2x–10x mismatch — planner estimate is noticeably off
              ratio_class = "text-orange-600 bg-orange-100"
            else
              # Within 2x — estimate is fine
              ratio_class = "text-blue-600 bg-blue-100"
            end
          else
            ratio_class = "text-red-600 bg-red-100 font-bold"
          end

          title_html += " <span class=\"#{ratio_class} px-2 py-1 rounded\">#{number_with_delimiter(actual)} rows"
          if ratio_class.include?("red")
            title_html += " ⚠️ (est: #{number_with_delimiter(estimated)})"
          elsif ratio_class.include?("orange")
            title_html += " ⚠ (est: #{number_with_delimiter(estimated)})"
          else
            title_html += " (est: #{number_with_delimiter(estimated)})"
          end
          title_html += "</span>"
        elsif node["Plan Rows"]
          title_html += " <span class=\"text-blue-600 bg-blue-100 px-2 py-1 rounded\">#{number_with_delimiter(node["Plan Rows"])} rows</span>"
        end

        # Add warning badges
        warnings.each do |warning|
          case warning[:type]
          when "seq-scan"
            badge_class = "bg-red-100 text-red-800"
          when "sort"
            badge_class = "bg-yellow-100 text-yellow-800"
          when "nested-loop"
            badge_class = "bg-green-100 text-green-800"
          when "fanout"
            badge_class = "bg-blue-100 text-blue-800"
          else
            badge_class = "bg-gray-100 text-gray-800"
          end

          title_html += " <span class=\"inline-flex items-center px-2 py-1 rounded text-xs font-medium #{badge_class}\">#{ERB::Util.html_escape(warning[:text])}</span>"
        end

        title_html
      end

      def render_node_details(node)
        details_html = '<div class="p-4 bg-gray-50 border-t border-gray-200"><div class="grid grid-cols-1 md:grid-cols-2 gap-4">'

        # Show key plan details
        details = []

        if node["Startup Cost"] && node["Total Cost"]
          details << [ "Cost", "#{node["Startup Cost"]}..#{node["Total Cost"]}", "Startup cost (before first row) to total cost (all rows). Arbitrary units — compare relative to other nodes." ]
        end

        if @analyze
          if node["Actual Startup Time"] && node["Actual Total Time"]
            details << [ "Actual Time", "#{node["Actual Startup Time"]}..#{node["Actual Total Time"]} ms", "Real time: from start until all rows returned for this node." ]
          end

          if node["Actual Loops"] && node["Actual Loops"] > 1
            details << [ "Loops", node["Actual Loops"].to_s, "Number of times this operation was repeated (e.g. once per row from a parent join)." ]
          end

          if node["Shared Hit Blocks"]
            buffers = []
            buffers << "hit=#{node["Shared Hit Blocks"]}" if node["Shared Hit Blocks"] > 0
            buffers << "read=#{node["Shared Read Blocks"]}" if node["Shared Read Blocks"] && node["Shared Read Blocks"] > 0
            buffers << "written=#{node["Shared Written Blocks"]}" if node["Shared Written Blocks"] && node["Shared Written Blocks"] > 0
            details << [ "Buffers", buffers.join(", "), "Shared memory pages accessed. 'hit' = cached in RAM, 'read' = fetched from disk." ] if buffers.any?
          end
        end

        # Index-specific details
        if node["Index Cond"]
          details << [ "Index Condition", node["Index Cond"], "The WHERE clause condition evaluated using the index for fast lookup." ]
        end

        if node["Recheck Cond"]
          details << [ "Recheck Condition", node["Recheck Cond"], "Condition re-verified against actual rows after a bitmap scan." ]
        end

        if node["Filter"]
          details << [ "Filter", node["Filter"], "Rows matching the scan are then filtered by this condition. Rows that don't match are discarded." ]
        end

        if node["Rows Removed by Filter"] && @analyze
          removed = node["Rows Removed by Filter"]
          actual = node["Actual Rows"] || 0
          total = actual + removed
          if removed > 0
            efficiency = total > 0 ? ((actual.to_f / total) * 100).round(1) : 0
            details << [ "Filter Efficiency", "#{efficiency}% (#{number_with_delimiter(removed)} rows filtered out)", "Percentage of scanned rows that matched the filter. Low efficiency may indicate a missing or suboptimal index." ]
          end
        end

        if node["Join Type"]
          details << [ "Join Type", node["Join Type"], "How two result sets are combined (e.g. Hash, Nested Loop, Merge)." ]
        end

        if node["Hash Cond"]
          details << [ "Hash Condition", node["Hash Cond"], "The equality condition used to match rows in a hash join." ]
        end

        if node["Sort Key"]
          sort_keys = node["Sort Key"].is_a?(Array) ? node["Sort Key"].join(", ") : node["Sort Key"]
          details << [ "Sort Key", sort_keys, "Column(s) used to order the result set." ]
        end

        if node["Sort Method"] && @analyze
          sort_info = node["Sort Method"]
          if node["Sort Space Used"]
            sort_info += " (#{node["Sort Space Used"]}kB"
            sort_info += node["Sort Space Type"] == "Disk" ? " on disk" : " in memory"
            sort_info += ")"
          end
          details << [ "Sort Method", sort_info, "Algorithm used for sorting. In-memory is fast; disk-based sorting indicates insufficient work_mem." ]
        end

        # Split details into two columns
        left_details = details.first((details.length + 1) / 2)
        right_details = details.drop(left_details.length)

        [ left_details, right_details ].each do |column_details|
          details_html += '<div class="space-y-2">'
          column_details.each do |label, value, explanation|
            details_html += <<~HTML
              <div class="text-xs">
                <dt class="font-medium text-gray-600">#{ERB::Util.html_escape(label)}:</dt>
                <dd class="mt-1 text-gray-900 font-mono break-words">#{ERB::Util.html_escape(value)}</dd>
            HTML
            if explanation
              details_html += <<~HTML
                <dd class="mt-0.5 text-gray-400 font-sans italic">#{ERB::Util.html_escape(explanation)}</dd>
              HTML
            end
            details_html += "</div>"
          end
          details_html += "</div>"
        end

        details_html += "</div></div>"
        details_html
      end

      def detect_warnings(node)
        warnings = []

        # Enhanced Seq Scan warning with table name
        if node["Node Type"] == "Seq Scan"
          table_name = node["Relation Name"] || "table"
          row_count = node["Plan Rows"] || 0

          if row_count > 10000
            warnings << { type: "seq-scan", text: "Large Seq Scan (#{number_with_delimiter(row_count)} rows on #{table_name})" }
          elsif row_count > 1000
            warnings << { type: "seq-scan", text: "Seq Scan (#{table_name})" }
          end
        end

        # Bitmap Heap Scan warnings
        if node["Node Type"] == "Bitmap Heap Scan" && node["Plan Rows"] && node["Plan Rows"] > 10000
          warnings << { type: "sort", text: "Large Bitmap Scan" }
        end

        # Large sort warning
        if node["Node Type"] == "Sort" && node["Plan Rows"] && node["Plan Rows"] > 10000
          warnings << { type: "sort", text: "Large Sort (#{number_with_delimiter(node["Plan Rows"])} rows)" }
        end

        # Nested loop with large inner
        if node["Node Type"] == "Nested Loop" && node["Plans"]
          inner_rows = node["Plans"].map { |p| p["Plan Rows"] || 0 }.max
          if inner_rows && inner_rows > 1000
            warnings << { type: "nested-loop", text: "Large Nested Loop (#{number_with_delimiter(inner_rows)} inner rows)" }
          end
        end

        # Row explosion (fanout)
        if @analyze && node["Actual Rows"] && node["Plan Rows"]
          actual = node["Actual Rows"]
          estimated = node["Plan Rows"]
          if estimated > 0 && actual > estimated * 10
            ratio = (actual.to_f / estimated).round(1)
            warnings << { type: "fanout", text: "Row Explosion (#{ratio}x estimate)" }
          end
        end

        # Index usage analysis
        if node["Node Type"].include?("Index") && node["Index Name"]
          # This is good - using an index
          # Could add positive feedback here in the future
        elsif node["Node Type"] == "Seq Scan" && node["Filter"]
          # Sequential scan with filter suggests missing index opportunity
          warnings << { type: "seq-scan", text: "Filtered Seq Scan (missing index?)" }
        end

        warnings
      end

      def has_children?(node)
        node["Plans"] && node["Plans"].any?
      end

      def find_hotspots(plan_node, hotspots = [])
        return hotspots unless @analyze

        # Add this node if it's slow
        if plan_node["Actual Total Time"] && plan_node["Actual Total Time"] > 10
          node_desc = "#{plan_node["Node Type"]}"
          node_desc += " on #{plan_node["Relation Name"]}" if plan_node["Relation Name"]
          node_desc += " (#{plan_node["Actual Total Time"]}ms)"
          hotspots << node_desc
        end

        # Recurse into children
        if plan_node["Plans"]
          plan_node["Plans"].each do |child|
            find_hotspots(child, hotspots)
          end
        end

        # Sort by time descending
        hotspots.sort_by! do |desc|
          match = desc.match(/\((\d+\.?\d*)ms\)/)
          match ? -match[1].to_f : 0
        end

        hotspots
      end

      def number_with_delimiter(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      def analyze_index_usage(plan_node, analysis = { index_scans: 0, total_scans: 0, indexes_used: [], warnings: [], seq_scans: [] })
        node_type = plan_node["Node Type"]

        # Count scan operations
        if node_type.include?("Scan") || node_type.include?("Seek")
          analysis[:total_scans] += 1

          if node_type.include?("Index") || node_type == "Bitmap Index Scan"
            analysis[:index_scans] += 1

            # Track which indexes are being used
            if plan_node["Index Name"]
              index_name = plan_node["Index Name"]
              relation = plan_node["Relation Name"]
              full_name = relation ? "#{relation}.#{index_name}" : index_name
              analysis[:indexes_used] << full_name unless analysis[:indexes_used].include?(full_name)
            end
          elsif node_type == "Seq Scan"
            table_name = plan_node["Relation Name"] || "unknown table"
            row_count = plan_node["Plan Rows"] || 0

            # Collect columns from filter conditions for index suggestions
            filter_cols = []
            filter_cols += extract_columns_from_condition(plan_node["Filter"]) if plan_node["Filter"]

            analysis[:seq_scans] << {
              table: table_name,
              rows: row_count,
              filter: plan_node["Filter"],
              columns: filter_cols
            }

            if row_count > 10000
              analysis[:warnings] << "Large sequential scan on #{table_name} (#{number_with_delimiter(row_count)} rows)"
            elsif row_count > 1000 && plan_node["Filter"]
              analysis[:warnings] << "Sequential scan with filter on #{table_name} - consider adding index"
            end
          end
        end

        # Recurse into child nodes
        if plan_node["Plans"]
          plan_node["Plans"].each do |child|
            analyze_index_usage(child, analysis)
          end
        end

        analysis
      end

      def collect_buffer_stats(node, stats = { hit_blocks: 0, read_blocks: 0, written_blocks: 0, total_blocks: 0 })
        if node["Shared Hit Blocks"]
          stats[:hit_blocks] += node["Shared Hit Blocks"].to_i
          stats[:total_blocks] += node["Shared Hit Blocks"].to_i
        end
        if node["Shared Read Blocks"]
          stats[:read_blocks] += node["Shared Read Blocks"].to_i
          stats[:total_blocks] += node["Shared Read Blocks"].to_i
        end
        if node["Shared Written Blocks"]
          stats[:written_blocks] += node["Shared Written Blocks"].to_i
        end

        if node["Plans"]
          node["Plans"].each { |child| collect_buffer_stats(child, stats) }
        end

        stats
      end

      def generate_recommendations(root_plan, index_analysis, buffer_stats)
        recs = []
        plan = root_plan["Plan"]
        execution_time = root_plan["Execution Time"]
        planning_time = root_plan["Planning Time"]

        # Walk the entire plan tree collecting issues
        walk_plan_for_recommendations(plan, recs)

        # Planning time vs execution time
        if planning_time && execution_time && planning_time > 0 && execution_time > 0
          if planning_time > execution_time * 2 && planning_time > 5
            recs << {
              severity: :info,
              title: "Planning time exceeds execution time",
              description: "The query planner spent #{planning_time}ms planning but only #{execution_time}ms executing. For frequently-run queries this overhead adds up.",
              action: "Consider using prepared statements to skip repeated planning: connection.prepare('my_query', sql)"
            }
          end
        end

        # Cache hit ratio
        if buffer_stats && buffer_stats[:total_blocks] > 0
          hit_ratio = (buffer_stats[:hit_blocks].to_f / buffer_stats[:total_blocks]) * 100
          if hit_ratio < 90 && buffer_stats[:read_blocks] > 10
            recs << {
              severity: :warning,
              title: "Low cache hit ratio (#{hit_ratio.round(1)}%)",
              description: "#{buffer_stats[:read_blocks]} pages were read from disk instead of cache. This slows queries significantly, especially under load.",
              action: "Increase shared_buffers in postgresql.conf, or run the query again (it may now be cached)."
            }
          end
        end

        # Sequential scan warnings with specific index suggestions
        if index_analysis[:total_scans] > 0 && index_analysis[:index_scans] == 0
          seq_scans = index_analysis[:seq_scans] || []
          index_suggestions = seq_scans.select { |s| s[:columns].any? }.map do |scan|
            cols = scan[:columns].join(", ")
            "CREATE INDEX idx_#{scan[:table]}_on_#{scan[:columns].first} ON #{scan[:table]} (#{cols});"
          end

          if index_suggestions.any?
            recs << {
              severity: :warning,
              title: "No indexes used",
              description: "All #{index_analysis[:total_scans]} scan(s) in this query are sequential scans. This means PostgreSQL is reading entire tables to find matching rows.",
              action: index_suggestions.join("\n")
            }
          else
            # Couldn't extract columns — list the tables at least
            tables = seq_scans.map { |s| s[:table] }.uniq
            recs << {
              severity: :warning,
              title: "No indexes used",
              description: "All #{index_analysis[:total_scans]} scan(s) in this query are sequential scans on #{tables.join(', ')}. This means PostgreSQL is reading entire tables to find matching rows.",
              action: "Add indexes on the columns used in WHERE, JOIN, and ORDER BY clauses for: #{tables.join(', ')}"
            }
          end
        end

        # Slow query overall
        if execution_time && execution_time > 1000
          recs << {
            severity: :critical,
            title: "Slow query (#{execution_time}ms)",
            description: "This query took over 1 second to execute. Users will notice this delay. Consider optimizing the query or adding caching.",
            action: nil
          }
        elsif execution_time && execution_time > 100
          recs << {
            severity: :warning,
            title: "Moderately slow query (#{execution_time}ms)",
            description: "This query took over 100ms. It's acceptable for background jobs but may be too slow for web requests where < 50ms is ideal.",
            action: nil
          }
        end

        recs
      end

      def walk_plan_for_recommendations(node, recs)
        node_type = node["Node Type"]

        # Seq Scan with filter on a table
        if node_type == "Seq Scan" && node["Filter"]
          table = node["Relation Name"] || "table"
          rows = @analyze ? (node["Actual Rows"] || node["Plan Rows"] || 0) : (node["Plan Rows"] || 0)
          removed = node["Rows Removed by Filter"] || 0

          if rows + removed > 1000
            filter_cols = extract_columns_from_condition(node["Filter"])
            col_suggestion = filter_cols.any? ? filter_cols.join(", ") : "the filtered column(s)"

            recs << {
              severity: :critical,
              title: "Sequential scan with filter on '#{table}'",
              description: "PostgreSQL scanned #{number_with_delimiter(rows + removed)} rows but only kept #{number_with_delimiter(rows)} (#{removed > 0 ? ((rows.to_f / (rows + removed)) * 100).round(1) : 100}% selectivity). A targeted index would avoid scanning irrelevant rows.",
              action: "CREATE INDEX idx_#{table}_on_#{filter_cols.first || 'column'} ON #{table} (#{col_suggestion});"
            }
          end
        end

        # Disk-based sort
        if node_type == "Sort" && @analyze && node["Sort Space Type"] == "Disk"
          space = node["Sort Space Used"] || 0
          recs << {
            severity: :warning,
            title: "Sort spilled to disk (#{space}kB)",
            description: "The sort couldn't fit in memory and used disk, which is much slower. This happens when work_mem is too small for the data being sorted.",
            action: "SET work_mem = '#{[ (space * 2 / 1024.0).ceil, 4 ].max}MB'; -- or increase work_mem in postgresql.conf"
          }
        end

        # Large in-memory sort
        if node_type == "Sort" && @analyze && node["Sort Space Type"] == "Memory" && (node["Sort Space Used"] || 0) > 10000
          recs << {
            severity: :info,
            title: "Large in-memory sort (#{node["Sort Space Used"]}kB)",
            description: "The sort fits in memory but uses significant space. If this query runs concurrently, total memory usage could be high.",
            action: nil
          }
        end

        # Nested loop with many iterations
        if node_type == "Nested Loop" && @analyze && node["Actual Loops"] && node["Actual Loops"] > 100
          recs << {
            severity: :warning,
            title: "Nested loop with #{number_with_delimiter(node["Actual Loops"])} iterations",
            description: "The inner side of this join is executed #{number_with_delimiter(node["Actual Loops"])} times. If the inner operation is not an index lookup, this can be extremely slow.",
            action: "Consider restructuring the query to allow a hash join, or ensure the inner table has appropriate indexes."
          }
        end

        # Large row estimate mismatch
        if @analyze && node["Actual Rows"] && node["Plan Rows"]
          actual = node["Actual Rows"]
          estimated = node["Plan Rows"]
          abs_diff = (actual - estimated).abs
          ratio = estimated > 0 ? (actual.to_f / estimated) : 0

          if abs_diff > 1000 && (ratio > 10 || ratio < 0.1)
            table = node["Relation Name"] || "the involved table"
            recs << {
              severity: :warning,
              title: "Row estimate off by #{ratio > 1 ? "#{ratio.round(0)}x" : "#{(1.0 / ratio).round(0)}x"} on #{node_type}",
              description: "PostgreSQL estimated #{number_with_delimiter(estimated)} rows but got #{number_with_delimiter(actual)}. Bad estimates lead to suboptimal plan choices (wrong join type, wrong scan method).",
              action: "ANALYZE #{table}; -- updates table statistics so the planner makes better estimates"
            }
          end
        end

        # Hash join with large buckets
        if node_type == "Hash" && @analyze
          if node["Peak Memory Usage"] && node["Peak Memory Usage"] > 100_000
            recs << {
              severity: :info,
              title: "Large hash table (#{(node["Peak Memory Usage"] / 1024.0).round(1)}MB)",
              description: "Building the hash table for this join used significant memory. Under concurrent load, this could cause memory pressure.",
              action: "SET work_mem = '#{[ (node["Peak Memory Usage"] / 512.0).ceil, 4 ].max}MB'; -- ensure enough memory for the hash"
            }
          end
        end

        # Bitmap Heap Scan with many recheck rows
        if node_type == "Bitmap Heap Scan" && @analyze && node["Rows Removed by Index Recheck"] && node["Rows Removed by Index Recheck"] > 1000
          recs << {
            severity: :info,
            title: "Bitmap scan with heavy recheck",
            description: "#{number_with_delimiter(node["Rows Removed by Index Recheck"])} rows were rechecked after the bitmap index scan. This happens when the bitmap becomes lossy (too many results).",
            action: "Increase work_mem to keep more exact page references, or add a more selective index."
          }
        end

        # Correlated subquery (SubPlan node)
        if node_type == "SubPlan" || node_type.start_with?("SubPlan")
          loops = node["Actual Loops"] || node["Plan Rows"] || 0
          recs << {
            severity: loops > 100 ? :critical : :warning,
            title: "Correlated subquery detected",
            description: "A subquery is being executed once per row from the outer query#{loops > 1 ? " (#{number_with_delimiter(loops)} times)" : ""}. This is one of the most common causes of slow queries.",
            action: "Rewrite the correlated subquery as a JOIN or use a lateral join. Example: SELECT ... FROM outer_table LEFT JOIN (subquery) ON ... instead of SELECT ..., (SELECT ...) FROM outer_table"
          }
        end

        # Also catch SubPlan via parent node's Plans having subplan-type entries
        if node["Subplan Name"] || (node["Parent Relationship"] == "SubPlan")
          loops = @analyze ? (node["Actual Loops"] || 0) : (node["Plan Rows"] || 0)
          unless recs.any? { |r| r[:title] == "Correlated subquery detected" }
            recs << {
              severity: loops > 100 ? :critical : :warning,
              title: "Correlated subquery detected",
              description: "A subquery (#{node["Subplan Name"] || node["Node Type"]}) runs for each row of the outer query#{loops > 1 ? " (#{number_with_delimiter(loops)} executions)" : ""}. This pattern scales poorly with table size.",
              action: "Rewrite as a JOIN: replace WHERE col IN (SELECT ...) with an INNER JOIN, or WHERE EXISTS (SELECT ...) with a semi-join."
            }
          end
        end

        # CTE materialization warning
        if node_type == "CTE Scan"
          cte_name = node["CTE Name"] || "the CTE"
          recs << {
            severity: :info,
            title: "Materialized CTE: #{cte_name}",
            description: "The CTE '#{cte_name}' is materialized into a temporary result set before being scanned. If the CTE result is large or the outer query filters most rows, this can be wasteful.",
            action: "WITH #{cte_name} AS NOT MATERIALIZED (SELECT ...) -- allows PostgreSQL to inline the CTE and apply outer filters (requires PostgreSQL 12+)"
          }
        end

        # Index Only Scan with high heap fetches
        if node_type == "Index Only Scan" && @analyze && node["Heap Fetches"]
          heap_fetches = node["Heap Fetches"]
          actual_rows = node["Actual Rows"] || 1
          if heap_fetches > 0 && actual_rows > 0
            fetch_ratio = (heap_fetches.to_f / actual_rows * 100).round(1)
            if fetch_ratio > 50
              table = node["Relation Name"] || "the table"
              recs << {
                severity: fetch_ratio > 90 ? :warning : :info,
                title: "Index Only Scan falling back to heap (#{fetch_ratio}%)",
                description: "#{number_with_delimiter(heap_fetches)} of #{number_with_delimiter(actual_rows)} rows required a heap fetch because the visibility map is out of date. This negates most of the benefit of an index-only scan.",
                action: "VACUUM #{table}; -- refreshes the visibility map so future index-only scans can skip heap fetches"
              }
            end
          end
        end

        # Recurse
        if node["Plans"]
          node["Plans"].each { |child| walk_plan_for_recommendations(child, recs) }
        end
      end

      def extract_columns_from_condition(condition)
        return [] unless condition.is_a?(String)

        # PostgreSQL EXPLAIN outputs conditions like:
        #   (status = 'active'::text)
        #   ((scheduled_at >= '2026-01-01'::timestamp) AND (scheduled_at <= '2026-12-31'::timestamp))
        #   (users.email = 'test@example.com'::text)
        #   ((role)::text = 'admin'::text)

        columns = []

        # Match table.column references (e.g., users.email)
        columns += condition.scan(/(\w+)\.(\w+)/).map { |_table, col| col }

        # Match standalone column in parens before operator: (column_name = ...) or (column_name >= ...)
        columns += condition.scan(/\((\w+)\s*[=<>!]/).map(&:first)

        # Match ((column)::type ...) cast pattern
        columns += condition.scan(/\(\((\w+)\)::/).map(&:first)

        # Match column BETWEEN, column IN, column IS patterns
        columns += condition.scan(/\((\w+)\s+(?:BETWEEN|IN|IS)\b/i).map(&:first)

        # Filter out common noise
        noise = %w[true false null text integer bigint timestamp date boolean numeric float double].map(&:downcase)
        columns = columns.uniq.reject { |c| noise.include?(c.downcase) || c.length < 2 }
        columns.first(5)
      end
    end
  end
end
