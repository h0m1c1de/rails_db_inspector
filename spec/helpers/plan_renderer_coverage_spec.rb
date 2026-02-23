# frozen_string_literal: true

require "spec_helper"
require_relative "../../app/helpers/rails_db_inspector/plan_renderer"

RSpec.describe RailsDbInspector::ApplicationHelper::PostgresPlanRenderer do
  def build_renderer(plan_data)
    described_class.new(plan_data)
  end

  describe "#render_summary with index analysis sections" do
    it "renders index analysis when indexes are used" do
      plan_data = {
        plan: [ {
          "Execution Time" => 1.0,
          "Planning Time" => 0.5,
          "Plan" => {
            "Node Type" => "Index Scan",
            "Index Name" => "idx_users_email",
            "Relation Name" => "users",
            "Total Cost" => 1.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 1,
            "Actual Rows" => 1,
            "Actual Total Time" => 0.5,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 32,
            "Shared Hit Blocks" => 10,
            "Shared Read Blocks" => 0
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_summary
      expect(html).to include("Index Analysis")
      expect(html).to include("Indexes Used")
    end

    it "renders warnings in index analysis" do
      plan_data = {
        plan: [ {
          "Execution Time" => 50.0,
          "Planning Time" => 0.5,
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 5000.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 50000,
            "Actual Rows" => 50000,
            "Actual Total Time" => 50.0,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 32,
            "Filter" => "(status = 'active')",
            "Rows Removed by Filter" => 40000,
            "Shared Hit Blocks" => 100,
            "Shared Read Blocks" => 50
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_summary
      expect(html).to include("Recommendations")
    end

    it "renders performance hotspots" do
      plan_data = {
        plan: [ {
          "Execution Time" => 100.0,
          "Planning Time" => 0.5,
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 1000.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 10000,
            "Actual Rows" => 10000,
            "Actual Total Time" => 100.0,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 32,
            "Shared Hit Blocks" => 50,
            "Shared Read Blocks" => 0
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_summary
      expect(html).to include("Performance Hotspots")
    end

    it "renders buffer stats summary with Actual Rows" do
      plan_data = {
        plan: [ {
          "Execution Time" => 1.0,
          "Planning Time" => 0.5,
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Total Cost" => 10.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100,
            "Actual Rows" => 100,
            "Actual Total Time" => 1.0,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 32,
            "Shared Hit Blocks" => 50,
            "Shared Read Blocks" => 5,
            "Shared Written Blocks" => 1
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_summary
      expect(html).to include("Execution Summary")
    end

    it "renders recommendations with different severities" do
      plan_data = {
        plan: [ {
          "Execution Time" => 2000.0,
          "Planning Time" => 5000.0,
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "big_table",
            "Total Cost" => 50000.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100000,
            "Actual Rows" => 100000,
            "Actual Total Time" => 2000.0,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 64,
            "Filter" => "(status = 'active')",
            "Rows Removed by Filter" => 90000,
            "Shared Hit Blocks" => 100,
            "Shared Read Blocks" => 500
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_summary
      expect(html).to include("Recommendations")
    end

    it "renders cache hit ratio" do
      plan_data = {
        plan: [ {
          "Execution Time" => 1.0,
          "Planning Time" => 0.5,
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Total Cost" => 10.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100,
            "Actual Rows" => 100,
            "Actual Total Time" => 1.0,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 32,
            "Shared Hit Blocks" => 90,
            "Shared Read Blocks" => 10
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_summary
      expect(html).to include("Cache Hit Ratio")
    end
  end

  describe "#render_tree with detailed node types" do
    it "renders index scan nodes with index name" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Index Scan",
            "Index Name" => "idx_users_email",
            "Relation Name" => "users",
            "Total Cost" => 1.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 1,
            "Plan Width" => 32,
            "Index Cond" => "(email = 'test@example.com')"
          }
        } ],
        analyze: false
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("Index Scan")
      expect(html).to include("idx_users_email")
      expect(html).to include("users")
    end

    it "renders seq scan with filter" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 1000.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 10000,
            "Plan Width" => 32,
            "Filter" => "(status = 'active')"
          }
        } ],
        analyze: false
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("Seq Scan")
      expect(html).to include("Filter")
      expect(html).to include("status")
    end

    it "renders analyze data with timing and row counts" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 100.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100,
            "Actual Rows" => 100,
            "Actual Total Time" => 5.0,
            "Actual Startup Time" => 0.1,
            "Plan Width" => 32,
            "Actual Loops" => 1
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("5.0")
      expect(html).to include("100 rows")
    end

    it "renders analyze data with large time (>100ms warning styling)" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 100.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100,
            "Actual Rows" => 100,
            "Actual Total Time" => 500.0,
            "Actual Startup Time" => 0.1,
            "Plan Width" => 32
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("500.0")
      expect(html).to include("text-red-600")
    end

    it "renders row estimate mismatch (10x+)" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 100.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 10,
            "Actual Rows" => 10000,
            "Actual Total Time" => 50.0,
            "Actual Startup Time" => 0.1,
            "Plan Width" => 32
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("10,000 rows")
      expect(html).to include("est:")
    end

    it "renders moderate row mismatch (2x-10x)" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 100.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100,
            "Actual Rows" => 500,
            "Actual Total Time" => 5.0,
            "Actual Startup Time" => 0.1,
            "Plan Width" => 32
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("500 rows")
      expect(html).to include("orange")
    end

    it "renders node details with buffers" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 100.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100,
            "Actual Rows" => 100,
            "Actual Total Time" => 5.0,
            "Actual Startup Time" => 0.1,
            "Plan Width" => 32,
            "Shared Hit Blocks" => 50,
            "Shared Read Blocks" => 5,
            "Shared Written Blocks" => 1,
            "Actual Loops" => 3
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("Buffers")
      expect(html).to include("hit=50")
      expect(html).to include("Loops")
    end

    it "renders filter efficiency" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 100.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100,
            "Actual Rows" => 100,
            "Actual Total Time" => 5.0,
            "Actual Startup Time" => 0.1,
            "Plan Width" => 32,
            "Filter" => "(status = 'active')",
            "Rows Removed by Filter" => 900
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("Filter Efficiency")
    end

    it "renders join details" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Hash Join",
            "Join Type" => "Inner",
            "Hash Cond" => "(users.id = posts.user_id)",
            "Total Cost" => 200.0,
            "Startup Cost" => 10.0,
            "Plan Rows" => 500,
            "Plan Width" => 64,
            "Plans" => [
              {
                "Node Type" => "Seq Scan",
                "Relation Name" => "users",
                "Total Cost" => 50.0,
                "Startup Cost" => 0.0,
                "Plan Rows" => 100,
                "Plan Width" => 32
              },
              {
                "Node Type" => "Hash",
                "Total Cost" => 100.0,
                "Startup Cost" => 0.0,
                "Plan Rows" => 500,
                "Plan Width" => 32,
                "Plans" => [ {
                  "Node Type" => "Seq Scan",
                  "Relation Name" => "posts",
                  "Total Cost" => 100.0,
                  "Startup Cost" => 0.0,
                  "Plan Rows" => 500,
                  "Plan Width" => 32
                } ]
              }
            ]
          }
        } ],
        analyze: false
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("Hash Join")
      expect(html).to include("Join Type")
      expect(html).to include("Hash Condition")
    end

    it "renders sort details" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Sort",
            "Sort Key" => [ "users.name" ],
            "Sort Method" => "quicksort",
            "Sort Space Used" => 100,
            "Sort Space Type" => "Memory",
            "Total Cost" => 50.0,
            "Startup Cost" => 40.0,
            "Plan Rows" => 500,
            "Actual Rows" => 500,
            "Actual Total Time" => 2.0,
            "Actual Startup Time" => 1.5,
            "Plan Width" => 32,
            "Plans" => [ {
              "Node Type" => "Seq Scan",
              "Relation Name" => "users",
              "Total Cost" => 30.0,
              "Startup Cost" => 0.0,
              "Plan Rows" => 500,
              "Plan Width" => 32
            } ]
          }
        } ],
        analyze: true
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("Sort Key")
      expect(html).to include("Sort Method")
      expect(html).to include("in memory")
    end

    it "renders recheck condition" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Bitmap Heap Scan",
            "Relation Name" => "users",
            "Recheck Cond" => "(email = 'test@example.com')",
            "Total Cost" => 10.0,
            "Startup Cost" => 5.0,
            "Plan Rows" => 1,
            "Plan Width" => 32,
            "Plans" => [ {
              "Node Type" => "Bitmap Index Scan",
              "Index Name" => "idx_users_email",
              "Total Cost" => 5.0,
              "Startup Cost" => 0.0,
              "Plan Rows" => 1,
              "Plan Width" => 0
            } ]
          }
        } ],
        analyze: false
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("Recheck Condition")
    end

    it "renders schema when not public" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Schema" => "custom_schema",
            "Total Cost" => 10.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 10,
            "Plan Width" => 32
          }
        } ],
        analyze: false
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("custom_schema")
    end

    it "does not append schema when it is public" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Schema" => "public",
            "Total Cost" => 10.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 10,
            "Plan Width" => 32
          }
        } ],
        analyze: false
      }

      html = build_renderer(plan_data).render_tree
      expect(html).not_to include("public")
    end

    it "renders plan rows when no actual rows (non-analyze)" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 10.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 42,
            "Plan Width" => 32
          }
        } ],
        analyze: false
      }

      html = build_renderer(plan_data).render_tree
      expect(html).to include("42 rows")
    end
  end

  describe "detect_warnings" do
    def warnings_for(node, analyze: false)
      renderer = build_renderer({ plan: [ { "Plan" => node } ], analyze: analyze })
      renderer.send(:detect_warnings, node)
    end

    it "warns on large seq scan (>10000 rows)" do
      w = warnings_for({ "Node Type" => "Seq Scan", "Relation Name" => "users", "Plan Rows" => 50000 })
      expect(w.any? { |x| x[:type] == "seq-scan" && x[:text].include?("Large") }).to be true
    end

    it "warns on medium seq scan (>1000 rows)" do
      w = warnings_for({ "Node Type" => "Seq Scan", "Relation Name" => "users", "Plan Rows" => 5000 })
      expect(w.any? { |x| x[:type] == "seq-scan" }).to be true
    end

    it "does not warn on small seq scan" do
      w = warnings_for({ "Node Type" => "Seq Scan", "Relation Name" => "users", "Plan Rows" => 50 })
      expect(w.select { |x| x[:text].include?("Large") || x[:text].include?("Seq Scan (") }).to be_empty
    end

    it "warns on large bitmap heap scan" do
      w = warnings_for({ "Node Type" => "Bitmap Heap Scan", "Plan Rows" => 50000 })
      expect(w.any? { |x| x[:text].include?("Large Bitmap Scan") }).to be true
    end

    it "warns on large sort" do
      w = warnings_for({ "Node Type" => "Sort", "Plan Rows" => 50000 })
      expect(w.any? { |x| x[:text].include?("Large Sort") }).to be true
    end

    it "warns on nested loop with large inner" do
      node = {
        "Node Type" => "Nested Loop",
        "Plans" => [
          { "Node Type" => "Index Scan", "Plan Rows" => 1 },
          { "Node Type" => "Seq Scan", "Plan Rows" => 5000 }
        ]
      }
      w = warnings_for(node)
      expect(w.any? { |x| x[:type] == "nested-loop" }).to be true
    end

    it "warns on row explosion (fanout)" do
      node = {
        "Node Type" => "Seq Scan",
        "Plan Rows" => 10,
        "Actual Rows" => 500,
        "Relation Name" => "users"
      }
      w = warnings_for(node, analyze: true)
      expect(w.any? { |x| x[:type] == "fanout" }).to be true
    end

    it "warns on filtered seq scan (missing index)" do
      w = warnings_for({
        "Node Type" => "Seq Scan",
        "Relation Name" => "users",
        "Plan Rows" => 100,
        "Filter" => "(status = 'active')"
      })
      expect(w.any? { |x| x[:text].include?("missing index") }).to be true
    end
  end

  describe "find_hotspots" do
    it "identifies slow nodes (>10ms)" do
      plan_node = {
        "Node Type" => "Seq Scan",
        "Relation Name" => "users",
        "Actual Total Time" => 50.0
      }
      renderer = build_renderer({ plan: [ { "Plan" => plan_node } ], analyze: true })
      hotspots = renderer.send(:find_hotspots, plan_node)
      expect(hotspots).to include(a_string_matching(/Seq Scan on users/))
    end

    it "recurses into child nodes" do
      plan_node = {
        "Node Type" => "Hash Join",
        "Actual Total Time" => 100.0,
        "Plans" => [ {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Actual Total Time" => 80.0
        } ]
      }
      renderer = build_renderer({ plan: [ { "Plan" => plan_node } ], analyze: true })
      hotspots = renderer.send(:find_hotspots, plan_node)
      expect(hotspots.length).to eq 2
    end

    it "returns empty when not in analyze mode" do
      plan_node = { "Node Type" => "Seq Scan", "Actual Total Time" => 50.0 }
      renderer = build_renderer({ plan: [ { "Plan" => plan_node } ], analyze: false })
      hotspots = renderer.send(:find_hotspots, plan_node)
      expect(hotspots).to be_empty
    end
  end

  describe "analyze_index_usage" do
    it "counts seq scans and captures filter columns" do
      node = {
        "Node Type" => "Seq Scan",
        "Relation Name" => "users",
        "Plan Rows" => 50000,
        "Filter" => "(status = 'active')"
      }
      renderer = build_renderer({ plan: [ { "Plan" => node } ], analyze: false })
      analysis = renderer.send(:analyze_index_usage, node)

      expect(analysis[:total_scans]).to eq 1
      expect(analysis[:index_scans]).to eq 0
      expect(analysis[:seq_scans].length).to eq 1
      expect(analysis[:seq_scans].first[:table]).to eq "users"
      expect(analysis[:warnings]).not_to be_empty
    end

    it "counts medium seq scan with filter" do
      node = {
        "Node Type" => "Seq Scan",
        "Relation Name" => "users",
        "Plan Rows" => 2000,
        "Filter" => "(email = 'test')"
      }
      renderer = build_renderer({ plan: [ { "Plan" => node } ], analyze: false })
      analysis = renderer.send(:analyze_index_usage, node)
      expect(analysis[:warnings].any? { |w| w.include?("consider adding index") }).to be true
    end

    it "tracks bitmap index scans" do
      node = {
        "Node Type" => "Bitmap Index Scan",
        "Index Name" => "idx_users_status",
        "Relation Name" => "users",
        "Plan Rows" => 100
      }
      renderer = build_renderer({ plan: [ { "Plan" => node } ], analyze: false })
      analysis = renderer.send(:analyze_index_usage, node)

      expect(analysis[:index_scans]).to eq 1
      expect(analysis[:indexes_used].first).to include("idx_users_status")
    end

    it "recurses into child nodes" do
      node = {
        "Node Type" => "Hash Join",
        "Plans" => [
          { "Node Type" => "Index Scan", "Index Name" => "idx", "Relation Name" => "users", "Plan Rows" => 1 },
          { "Node Type" => "Seq Scan", "Relation Name" => "posts", "Plan Rows" => 100 }
        ]
      }
      renderer = build_renderer({ plan: [ { "Plan" => node } ], analyze: false })
      analysis = renderer.send(:analyze_index_usage, node)
      expect(analysis[:total_scans]).to eq 2
      expect(analysis[:index_scans]).to eq 1
    end
  end

  describe "generate_recommendations" do
    def recs_for(root_plan, analyze: true)
      plan_data = { plan: [ root_plan ], analyze: analyze }
      renderer = build_renderer(plan_data)
      index_analysis = renderer.send(:analyze_index_usage, root_plan["Plan"])
      buffer_stats = renderer.send(:collect_buffer_stats, root_plan["Plan"])
      renderer.send(:generate_recommendations, root_plan, index_analysis, buffer_stats)
    end

    it "recommends prepared statements when planning > execution" do
      recs = recs_for({
        "Execution Time" => 1.0,
        "Planning Time" => 10.0,
        "Plan" => {
          "Node Type" => "Index Scan",
          "Index Name" => "idx",
          "Relation Name" => "users",
          "Total Cost" => 1.0,
          "Startup Cost" => 0.0,
          "Plan Rows" => 1,
          "Actual Rows" => 1,
          "Actual Total Time" => 1.0,
          "Actual Startup Time" => 0.0,
          "Plan Width" => 32
        }
      })
      expect(recs.any? { |r| r[:title].include?("Planning time") }).to be true
    end

    it "warns about low cache hit ratio" do
      recs = recs_for({
        "Execution Time" => 5.0,
        "Planning Time" => 0.5,
        "Plan" => {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Total Cost" => 100.0,
          "Startup Cost" => 0.0,
          "Plan Rows" => 1000,
          "Actual Rows" => 1000,
          "Actual Total Time" => 5.0,
          "Actual Startup Time" => 0.0,
          "Plan Width" => 32,
          "Shared Hit Blocks" => 10,
          "Shared Read Blocks" => 50
        }
      })
      expect(recs.any? { |r| r[:title].include?("cache hit ratio") }).to be true
    end

    it "flags slow queries (>1000ms)" do
      recs = recs_for({
        "Execution Time" => 2000.0,
        "Planning Time" => 0.5,
        "Plan" => {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Total Cost" => 100.0,
          "Startup Cost" => 0.0,
          "Plan Rows" => 100,
          "Actual Rows" => 100,
          "Actual Total Time" => 2000.0,
          "Actual Startup Time" => 0.0,
          "Plan Width" => 32
        }
      })
      expect(recs.any? { |r| r[:severity] == :critical && r[:title].include?("Slow query") }).to be true
    end

    it "flags moderately slow queries (>100ms)" do
      recs = recs_for({
        "Execution Time" => 200.0,
        "Planning Time" => 0.5,
        "Plan" => {
          "Node Type" => "Index Scan",
          "Index Name" => "idx",
          "Relation Name" => "users",
          "Total Cost" => 10.0,
          "Startup Cost" => 0.0,
          "Plan Rows" => 100,
          "Actual Rows" => 100,
          "Actual Total Time" => 200.0,
          "Actual Startup Time" => 0.0,
          "Plan Width" => 32
        }
      })
      expect(recs.any? { |r| r[:title].include?("Moderately slow") }).to be true
    end

    it "suggests indexes when no indexes are used" do
      recs = recs_for({
        "Execution Time" => 10.0,
        "Planning Time" => 0.5,
        "Plan" => {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Total Cost" => 100.0,
          "Startup Cost" => 0.0,
          "Plan Rows" => 1000,
          "Actual Rows" => 1000,
          "Actual Total Time" => 10.0,
          "Actual Startup Time" => 0.0,
          "Plan Width" => 32,
          "Filter" => "(status = 'active')",
          "Rows Removed by Filter" => 9000
        }
      })
      expect(recs.any? { |r| r[:title].include?("No indexes used") }).to be true
    end

    it "suggests indexes with CREATE INDEX action" do
      recs = recs_for({
        "Execution Time" => 10.0,
        "Planning Time" => 0.5,
        "Plan" => {
          "Node Type" => "Seq Scan",
          "Relation Name" => "users",
          "Total Cost" => 100.0,
          "Startup Cost" => 0.0,
          "Plan Rows" => 5000,
          "Actual Rows" => 5000,
          "Actual Total Time" => 10.0,
          "Actual Startup Time" => 0.0,
          "Plan Width" => 32,
          "Filter" => "(email = 'test')",
          "Rows Removed by Filter" => 45000
        }
      })
      idx_rec = recs.find { |r| r[:title].include?("No indexes used") }
      expect(idx_rec).not_to be_nil
      expect(idx_rec[:action]).to include("CREATE INDEX")
    end
  end

  describe "walk_plan_for_recommendations" do
    def walk_recs(node, analyze: true)
      plan_data = { plan: [ { "Plan" => node } ], analyze: analyze }
      renderer = build_renderer(plan_data)
      recs = []
      renderer.send(:walk_plan_for_recommendations, node, recs)
      recs
    end

    it "recommends index for seq scan with filter on large table" do
      recs = walk_recs({
        "Node Type" => "Seq Scan",
        "Relation Name" => "orders",
        "Filter" => "(status = 'active')",
        "Actual Rows" => 100,
        "Plan Rows" => 100,
        "Rows Removed by Filter" => 9900
      })
      expect(recs.any? { |r| r[:title].include?("Sequential scan with filter") }).to be true
      expect(recs.first[:action]).to include("CREATE INDEX")
    end

    it "warns on disk sort" do
      recs = walk_recs({
        "Node Type" => "Sort",
        "Sort Space Type" => "Disk",
        "Sort Space Used" => 50000,
        "Actual Rows" => 100000,
        "Plan Rows" => 100000
      })
      expect(recs.any? { |r| r[:title].include?("Sort spilled to disk") }).to be true
    end

    it "warns on large in-memory sort" do
      recs = walk_recs({
        "Node Type" => "Sort",
        "Sort Space Type" => "Memory",
        "Sort Space Used" => 20000,
        "Actual Rows" => 100000,
        "Plan Rows" => 100000
      })
      expect(recs.any? { |r| r[:title].include?("Large in-memory sort") }).to be true
    end

    it "warns on nested loop with many iterations" do
      recs = walk_recs({
        "Node Type" => "Nested Loop",
        "Actual Loops" => 5000,
        "Actual Rows" => 5000,
        "Plan Rows" => 5000
      })
      expect(recs.any? { |r| r[:title].include?("Nested loop") }).to be true
    end

    it "warns on large row estimate mismatch" do
      recs = walk_recs({
        "Node Type" => "Seq Scan",
        "Relation Name" => "users",
        "Plan Rows" => 10,
        "Actual Rows" => 50000
      })
      expect(recs.any? { |r| r[:title].include?("Row estimate off") }).to be true
    end

    it "warns on CTE Scan" do
      recs = walk_recs({
        "Node Type" => "CTE Scan",
        "CTE Name" => "active_users",
        "Plan Rows" => 100,
        "Actual Rows" => 100
      })
      expect(recs.any? { |r| r[:title].include?("Materialized CTE") }).to be true
    end

    it "warns on correlated subquery (SubPlan)" do
      recs = walk_recs({
        "Node Type" => "SubPlan",
        "Actual Loops" => 500,
        "Plan Rows" => 500,
        "Actual Rows" => 500
      })
      expect(recs.any? { |r| r[:title].include?("Correlated subquery") }).to be true
    end

    it "warns on subplan via parent relationship" do
      recs = walk_recs({
        "Node Type" => "Index Scan",
        "Parent Relationship" => "SubPlan",
        "Actual Loops" => 200,
        "Plan Rows" => 200,
        "Actual Rows" => 200
      })
      expect(recs.any? { |r| r[:title].include?("Correlated subquery") }).to be true
    end

    it "warns on index only scan with high heap fetches" do
      recs = walk_recs({
        "Node Type" => "Index Only Scan",
        "Relation Name" => "users",
        "Heap Fetches" => 900,
        "Actual Rows" => 1000,
        "Plan Rows" => 1000,
        "Index Name" => "idx_users_pk"
      })
      expect(recs.any? { |r| r[:title].include?("Index Only Scan falling back") }).to be true
    end

    it "warns on bitmap scan with heavy recheck" do
      recs = walk_recs({
        "Node Type" => "Bitmap Heap Scan",
        "Rows Removed by Index Recheck" => 5000,
        "Actual Rows" => 1000,
        "Plan Rows" => 1000
      })
      expect(recs.any? { |r| r[:title].include?("Bitmap scan with heavy recheck") }).to be true
    end

    it "warns on large hash table" do
      recs = walk_recs({
        "Node Type" => "Hash",
        "Peak Memory Usage" => 200_000,
        "Actual Rows" => 100000,
        "Plan Rows" => 100000
      })
      expect(recs.any? { |r| r[:title].include?("Large hash table") }).to be true
    end

    it "recurses into child nodes" do
      recs = walk_recs({
        "Node Type" => "Hash Join",
        "Actual Rows" => 100,
        "Plan Rows" => 100,
        "Plans" => [ {
          "Node Type" => "Seq Scan",
          "Relation Name" => "orders",
          "Filter" => "(total > 100)",
          "Actual Rows" => 500,
          "Plan Rows" => 500,
          "Rows Removed by Filter" => 4500
        } ]
      })
      expect(recs.any? { |r| r[:title].include?("Sequential scan with filter") }).to be true
    end
  end

  describe "extract_columns_from_condition" do
    def extract(condition)
      renderer = build_renderer({ plan: [], analyze: false })
      renderer.send(:extract_columns_from_condition, condition)
    end

    it "extracts table.column references" do
      cols = extract("(users.email = 'test@example.com')")
      expect(cols).to include("email")
    end

    it "extracts standalone column before operator" do
      cols = extract("(status = 'active')")
      expect(cols).to include("status")
    end

    it "extracts cast pattern ((column)::type)" do
      cols = extract("((role)::text = 'admin'::text)")
      expect(cols).to include("role")
    end

    it "extracts BETWEEN columns" do
      cols = extract("(created_at BETWEEN '2026-01-01' AND '2026-12-31')")
      expect(cols).to include("created_at")
    end

    it "filters out noise words like text, integer" do
      cols = extract("(text = 'something')")
      expect(cols).not_to include("text")
    end

    it "returns empty for nil condition" do
      expect(extract(nil)).to eq []
    end

    it "returns empty for non-string condition" do
      expect(extract(123)).to eq []
    end

    it "limits results to 5 columns" do
      condition = "(a = 1 AND b = 2 AND c = 3 AND d = 4 AND e = 5 AND f = 6 AND g = 7)"
      cols = extract(condition)
      expect(cols.length).to be <= 5
    end
  end
end
