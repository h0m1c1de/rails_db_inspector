# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::Explain::Sqlite do
  let(:connection) { double("connection") }
  subject(:explainer) { described_class.new(connection) }

  before do
    allow(connection).to receive(:quote_table_name) { |t| "\"#{t}\"" }
    allow(connection).to receive(:select_value).and_return(0)
  end

  describe "#explain" do
    context "without analyze" do
      it "runs EXPLAIN QUERY PLAN and returns structured plan" do
        result = double("result",
          columns: [ "id", "parent", "notused", "detail" ],
          rows: [ [ 2, 0, 0, "SCAN users" ] ]
        )

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN QUERY PLAN SELECT * FROM users")
          .and_return(result)

        output = explainer.explain("SELECT * FROM users")

        expect(output[:adapter]).to eq "sqlite"
        expect(output[:analyze]).to be false
        expect(output[:columns]).to eq [ "id", "parent", "notused", "detail" ]
        expect(output[:rows]).to eq [ [ 2, 0, 0, "SCAN users" ] ]
        expect(output[:plan].first["detail"]).to eq "SCAN users"
      end

      it "strips existing EXPLAIN QUERY PLAN prefix" do
        result = double("result", columns: [], rows: [])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN QUERY PLAN SELECT 1")
          .and_return(result)

        explainer.explain("EXPLAIN QUERY PLAN SELECT 1")
      end

      it "strips existing EXPLAIN prefix" do
        result = double("result", columns: [], rows: [])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN QUERY PLAN SELECT 1")
          .and_return(result)

        explainer.explain("EXPLAIN SELECT 1")
      end
    end

    context "with analyze" do
      it "calls select_only! for safety" do
        result = double("result", columns: [], rows: [])
        allow(connection).to receive(:exec_query).and_return(result)

        expect(RailsDbInspector::Explain).to receive(:select_only!).and_call_original

        explainer.explain("SELECT 1", analyze: true)
      end

      it "runs EXPLAIN QUERY PLAN with analyze flag" do
        result = double("result",
          columns: [ "id", "parent", "notused", "detail" ],
          rows: [ [ 2, 0, 0, "SEARCH TABLE users USING INDEX idx_users_email (email=?)" ] ]
        )

        allow(connection).to receive(:select_value).with(/SELECT COUNT/).and_return(500)

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN QUERY PLAN SELECT * FROM users WHERE email = 'test'")
          .and_return(result)

        output = explainer.explain("SELECT * FROM users WHERE email = 'test'", analyze: true)

        expect(output[:adapter]).to eq "sqlite"
        expect(output[:analyze]).to be true
        expect(output[:plan].first["detail"]).to include("SEARCH TABLE users")
      end
    end
  end

  describe "#collect_table_stats" do
    it "collects row counts for tables referenced in SCAN TABLE" do
      plan = [
        { "detail" => "SCAN TABLE users" },
        { "detail" => "SEARCH TABLE posts USING INDEX idx_posts_user_id (user_id=?)" }
      ]

      allow(connection).to receive(:select_value).with(/COUNT.*users/).and_return(1500)
      allow(connection).to receive(:select_value).with(/COUNT.*posts/).and_return(5000)

      stats = explainer.send(:collect_table_stats, plan)

      expect(stats["users"][:row_count]).to eq(1500)
      expect(stats["users"][:scan_type]).to eq("full_scan")
      expect(stats["users"][:uses_index]).to be false

      expect(stats["posts"][:row_count]).to eq(5000)
      expect(stats["posts"][:scan_type]).to eq("index_search")
      expect(stats["posts"][:uses_index]).to be true
    end

    it "handles errors gracefully when table doesn't exist" do
      plan = [ { "detail" => "SCAN TABLE missing_table" } ]

      allow(connection).to receive(:select_value).and_raise(StandardError.new("no such table"))

      stats = explainer.send(:collect_table_stats, plan)

      expect(stats["missing_table"][:row_count]).to be_nil
      expect(stats["missing_table"][:scan_type]).to eq("unknown")
    end

    it "returns empty hash for plans with no table references" do
      plan = [ { "detail" => "USE TEMP B-TREE FOR ORDER BY" } ]

      stats = explainer.send(:collect_table_stats, plan)
      expect(stats).to eq({})
    end

    it "deduplicates tables referenced multiple times" do
      plan = [
        { "detail" => "SCAN TABLE users" },
        { "detail" => "SCAN TABLE users" }
      ]

      expect(connection).to receive(:select_value).with(/COUNT.*users/).once.and_return(200)

      stats = explainer.send(:collect_table_stats, plan)
      expect(stats.keys).to eq(["users"])
    end
  end
end
