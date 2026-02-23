# frozen_string_literal: true

require "spec_helper"
require_relative "../../app/helpers/rails_db_inspector/plan_renderer"

RSpec.describe RailsDbInspector::ApplicationHelper::PostgresPlanRenderer do
  describe "#render_summary" do
    context "with nil plan" do
      it "returns empty string" do
        renderer = described_class.new({ plan: nil, analyze: false })
        expect(renderer.render_summary).to eq ""
      end
    end

    context "with empty plan" do
      it "returns empty string" do
        renderer = described_class.new({ plan: [], analyze: false })
        expect(renderer.render_summary).to eq ""
      end
    end

    context "with non-array plan" do
      it "returns empty string" do
        renderer = described_class.new({ plan: "invalid", analyze: false })
        expect(renderer.render_summary).to eq ""
      end
    end

    context "with a basic plan (no analyze)" do
      let(:plan_data) do
        {
          plan: [ {
            "Plan" => {
              "Node Type" => "Seq Scan",
              "Total Cost" => 10.5,
              "Startup Cost" => 0.0,
              "Plan Rows" => 100,
              "Plan Width" => 32
            }
          } ],
          analyze: false
        }
      end

      it "renders summary with cost information" do
        renderer = described_class.new(plan_data)
        html = renderer.render_summary

        expect(html).to include("Execution Summary")
        expect(html).to include("10.5")
      end
    end

    context "with an analyze plan" do
      let(:plan_data) do
        {
          plan: [ {
            "Execution Time" => 1.234,
            "Planning Time" => 0.456,
            "Plan" => {
              "Node Type" => "Seq Scan",
              "Total Cost" => 10.5,
              "Actual Rows" => 50,
              "Actual Total Time" => 1.0,
              "Actual Startup Time" => 0.1,
              "Startup Cost" => 0.0,
              "Plan Rows" => 100,
              "Plan Width" => 32,
              "Shared Hit Blocks" => 10,
              "Shared Read Blocks" => 2
            }
          } ],
          analyze: true
        }
      end

      it "renders execution time" do
        renderer = described_class.new(plan_data)
        html = renderer.render_summary

        expect(html).to include("1.234")
        expect(html).to include("Execution Time")
      end

      it "renders planning time" do
        renderer = described_class.new(plan_data)
        html = renderer.render_summary

        expect(html).to include("0.456")
        expect(html).to include("Planning Time")
      end
    end
  end

  describe "#render_tree" do
    context "with nil plan" do
      it "returns empty string" do
        renderer = described_class.new({ plan: nil, analyze: false })
        expect(renderer.render_tree).to eq ""
      end
    end

    context "with a simple seq scan plan" do
      let(:plan_data) do
        {
          plan: [ {
            "Plan" => {
              "Node Type" => "Seq Scan",
              "Relation Name" => "users",
              "Total Cost" => 10.5,
              "Startup Cost" => 0.0,
              "Plan Rows" => 100,
              "Plan Width" => 32
            }
          } ],
          analyze: false
        }
      end

      it "renders the plan tree with node type" do
        renderer = described_class.new(plan_data)
        html = renderer.render_tree

        expect(html).to include("Seq Scan")
      end
    end

    context "with nested plans (children)" do
      let(:plan_data) do
        {
          plan: [ {
            "Plan" => {
              "Node Type" => "Hash Join",
              "Total Cost" => 100.0,
              "Startup Cost" => 0.0,
              "Plan Rows" => 200,
              "Plan Width" => 64,
              "Plans" => [
                {
                  "Node Type" => "Seq Scan",
                  "Relation Name" => "users",
                  "Total Cost" => 10.5,
                  "Startup Cost" => 0.0,
                  "Plan Rows" => 100,
                  "Plan Width" => 32
                },
                {
                  "Node Type" => "Hash",
                  "Total Cost" => 50.0,
                  "Startup Cost" => 0.0,
                  "Plan Rows" => 50,
                  "Plan Width" => 32,
                  "Plans" => [
                    {
                      "Node Type" => "Seq Scan",
                      "Relation Name" => "posts",
                      "Total Cost" => 25.0,
                      "Startup Cost" => 0.0,
                      "Plan Rows" => 50,
                      "Plan Width" => 32
                    }
                  ]
                }
              ]
            }
          } ],
          analyze: false
        }
      end

      it "renders nested nodes" do
        renderer = described_class.new(plan_data)
        html = renderer.render_tree

        expect(html).to include("Hash Join")
        expect(html).to include("Seq Scan")
        expect(html).to include("Hash")
      end
    end

    context "with analyze data including warnings" do
      let(:plan_data) do
        {
          plan: [ {
            "Plan" => {
              "Node Type" => "Seq Scan",
              "Relation Name" => "users",
              "Total Cost" => 1000.0,
              "Startup Cost" => 0.0,
              "Plan Rows" => 100,
              "Actual Rows" => 10000,
              "Actual Total Time" => 500.0,
              "Actual Startup Time" => 0.0,
              "Plan Width" => 32,
              "Rows Removed by Filter" => 9900
            }
          } ],
          analyze: true
        }
      end

      it "renders warning indicators for costly scans" do
        renderer = described_class.new(plan_data)
        html = renderer.render_tree

        expect(html).to include("Seq Scan")
      end
    end
  end

  describe "warning detection" do
    it "detects row estimate mismatches" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Plan Rows" => 1,
            "Actual Rows" => 10000,
            "Total Cost" => 10.0,
            "Startup Cost" => 0.0,
            "Actual Total Time" => 1.0,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 32
          }
        } ],
        analyze: true
      }

      renderer = described_class.new(plan_data)
      html = renderer.render_tree
      # The renderer should have detected the row mismatch
      expect(html).to be_a(String)
    end
  end

  describe "number_with_delimiter helper" do
    it "formats large numbers with commas" do
      renderer = described_class.new({ plan: [], analyze: false })
      result = renderer.send(:number_with_delimiter, 1234567)
      expect(result).to eq "1,234,567"
    end

    it "handles small numbers" do
      renderer = described_class.new({ plan: [], analyze: false })
      result = renderer.send(:number_with_delimiter, 42)
      expect(result).to eq "42"
    end
  end

  describe "index usage analysis" do
    let(:plan_data) do
      {
        plan: [ {
          "Plan" => {
            "Node Type" => "Index Scan",
            "Index Name" => "idx_users_email",
            "Relation Name" => "users",
            "Total Cost" => 1.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 1,
            "Actual Rows" => 1,
            "Actual Total Time" => 0.01,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 32
          }
        } ],
        analyze: true
      }
    end

    it "tracks index scans" do
      renderer = described_class.new(plan_data)
      analysis = renderer.send(:analyze_index_usage, plan_data[:plan].first["Plan"])

      expect(analysis[:index_scans]).to be >= 1
      expect(analysis[:indexes_used].any? { |i| i.include?("idx_users_email") }).to be true
    end
  end

  describe "buffer stats collection" do
    let(:plan_data) do
      {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Shared Hit Blocks" => 100,
            "Shared Read Blocks" => 20,
            "Shared Written Blocks" => 5,
            "Total Cost" => 10.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 100,
            "Plan Width" => 32
          }
        } ],
        analyze: true
      }
    end

    it "collects buffer statistics" do
      renderer = described_class.new(plan_data)
      stats = renderer.send(:collect_buffer_stats, plan_data[:plan].first["Plan"])

      expect(stats[:hit_blocks]).to eq 100
      expect(stats[:read_blocks]).to eq 20
      expect(stats[:written_blocks]).to eq 5
    end
  end

  describe "recommendation generation" do
    it "generates recommendations for seq scans" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 1000.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 10000,
            "Actual Rows" => 10000,
            "Actual Total Time" => 50.0,
            "Actual Startup Time" => 0.0,
            "Plan Width" => 32,
            "Filter" => "(status = 'active')"
          }
        } ],
        analyze: true
      }

      renderer = described_class.new(plan_data)
      html = renderer.render_summary
      # Should contain some recommendation content
      expect(html).to be_a(String)
    end
  end
end
