# frozen_string_literal: true

require "spec_helper"
require_relative "../../app/helpers/rails_db_inspector/application_helper"

# Reuse or create test host
class HelperCoverageTestHost
  include RailsDbInspector::ApplicationHelper
  public *RailsDbInspector::ApplicationHelper.private_instance_methods(false)
end

RSpec.describe RailsDbInspector::ApplicationHelper, "coverage" do
  let(:helper) { HelperCoverageTestHost.new }

  def build_query(attrs = {})
    RailsDbInspector::QueryStore::Query.new(
      id: attrs[:id] || SecureRandom.hex(8),
      sql: attrs[:sql] || "SELECT * FROM users",
      name: attrs[:name] || "User Load",
      binds: attrs[:binds] || [],
      duration_ms: attrs[:duration_ms] || 1.0,
      connection_id: attrs[:connection_id] || 1,
      timestamp: attrs[:timestamp] || Time.now
    )
  end

  describe "#render_postgres_plan" do
    it "returns rendered summary + tree as html_safe string" do
      plan_data = {
        plan: [ {
          "Plan" => {
            "Node Type" => "Seq Scan",
            "Relation Name" => "users",
            "Total Cost" => 10.0,
            "Startup Cost" => 0.0,
            "Plan Rows" => 10,
            "Plan Width" => 32
          }
        } ],
        analyze: false
      }

      result = helper.render_postgres_plan(plan_data)
      expect(result).to be_a(ActiveSupport::SafeBuffer)
      expect(result).to include("Seq Scan")
    end
  end

  describe "#extract_controller_action_from_sql" do
    it "extracts simple controller and action" do
      q = build_query(sql: "/* controller='users', action='index' */ SELECT * FROM users")
      result = helper.extract_controller_action_from_sql(q)
      expect(result).to eq "UsersController#index"
    end

    it "handles namespaced controllers with /" do
      q = build_query(sql: "/* controller='api/v1/users', action='show' */ SELECT * FROM users")
      result = helper.extract_controller_action_from_sql(q)
      expect(result).to eq "Api::V1::UsersController#show"
    end

    it "falls back to query name when no comment" do
      q = build_query(sql: "SELECT * FROM users", name: "User Load")
      result = helper.extract_controller_action_from_sql(q)
      expect(result).to eq "User Load"
    end

    it "returns 'Unknown Query' when no name or comment" do
      q = build_query(sql: "SELECT * FROM users", name: "")
      result = helper.extract_controller_action_from_sql(q)
      expect(result).to eq "Unknown Query"
    end
  end

  describe "#determine_request_type_from_action" do
    it "returns :api for API namespaced controllers" do
      expect(helper.determine_request_type_from_action("Api::UsersController#index")).to eq :api
    end

    it "returns :web_request for controllers with new/edit actions" do
      expect(helper.determine_request_type_from_action("UsersController#new")).to eq :web_request
      expect(helper.determine_request_type_from_action("UsersController#edit")).to eq :web_request
    end

    it "returns :web_or_api for CRUD actions without new/edit" do
      expect(helper.determine_request_type_from_action("UsersController#index")).to eq :web_or_api
      expect(helper.determine_request_type_from_action("UsersController#show")).to eq :web_or_api
      expect(helper.determine_request_type_from_action("UsersController#create")).to eq :web_or_api
    end

    it "returns :model_operation for model-related names" do
      expect(helper.determine_request_type_from_action("User Load")).to eq :model_operation
      expect(helper.determine_request_type_from_action("Post Create")).to eq :model_operation
    end

    it "returns :schema for schema/migration names" do
      expect(helper.determine_request_type_from_action("Schema Check")).to eq :schema
      expect(helper.determine_request_type_from_action("Migration")).to eq :schema
    end

    it "returns :other for unrecognized names" do
      expect(helper.determine_request_type_from_action("something unknown")).to eq :other
    end
  end

  describe "#group_icon" do
    it "returns correct icon for each type" do
      expect(helper.group_icon(:api)).to eq "🔗"
      expect(helper.group_icon(:web_request)).to eq "🌐"
      expect(helper.group_icon(:web_or_api)).to eq "🔀"
      expect(helper.group_icon(:model_operation)).to eq "📊"
      expect(helper.group_icon(:schema)).to eq "🗂️"
      expect(helper.group_icon(:other)).to eq "💾"
    end
  end

  describe "#parse_timestamp" do
    it "handles Time objects" do
      t = Time.now
      expect(helper.parse_timestamp(t)).to eq t
    end

    it "handles Numeric (epoch) values" do
      epoch = 1700000000
      result = helper.parse_timestamp(epoch)
      expect(result).to eq Time.at(epoch)
    end

    it "handles String timestamps" do
      ts = "2024-01-15 12:30:00"
      result = helper.parse_timestamp(ts)
      expect(result).to be_a(Time)
    end

    it "returns Time.now on unparseable values" do
      allow(Time).to receive(:parse).and_raise(ArgumentError)
      before = Time.now
      result = helper.parse_timestamp("not-a-timestamp")
      after = Time.now
      expect(result).to be_between(before, after)
    end
  end

  describe "#format_group_time_range" do
    it "returns empty string for empty queries" do
      group = { queries: [], start_time: Time.now }
      expect(helper.format_group_time_range(group)).to eq ""
    end

    it "shows single time for <1s range" do
      t = Time.now
      group = {
        queries: [ build_query(timestamp: t) ],
        start_time: t
      }
      result = helper.format_group_time_range(group)
      expect(result).to match(/\d{2}:\d{2}:\d{2}/)
      expect(result).not_to include(" - ")
    end

    it "shows time range for >=1s range" do
      t = Time.now
      group = {
        queries: [ build_query(timestamp: t + 5) ],
        start_time: t
      }
      result = helper.format_group_time_range(group)
      expect(result).to include(" - ")
    end
  end

  describe "#time_gap_too_large?" do
    it "returns false when last_query is nil" do
      q = build_query
      expect(helper.send(:time_gap_too_large?, q, nil)).to be false
    end

    it "returns true when gap exceeds threshold" do
      t = Time.now
      q1 = build_query(timestamp: t)
      q2 = build_query(timestamp: t + 20)
      expect(helper.send(:time_gap_too_large?, q2, q1, 5.0)).to be true
    end

    it "returns false when gap is within threshold" do
      t = Time.now
      q1 = build_query(timestamp: t)
      q2 = build_query(timestamp: t + 2)
      expect(helper.send(:time_gap_too_large?, q2, q1, 5.0)).to be false
    end
  end

  describe "#normalize_sql" do
    it "removes SQL comments" do
      expect(helper.send(:normalize_sql, "/* app:web */ SELECT * FROM users")).to include("SELECT * FROM users")
    end

    it "replaces string literals" do
      expect(helper.send(:normalize_sql, "SELECT * FROM users WHERE name = 'Alice'")).to include("name = ?")
    end

    it "replaces $1 style params" do
      result = helper.send(:normalize_sql, "SELECT * FROM users WHERE id = $1")
      # $1 becomes $? because \d+ is replaced first, then $ prefix remains
      expect(result).to include("$?")
    end

    it "collapses whitespace" do
      result = helper.send(:normalize_sql, "SELECT  *  FROM   users")
      expect(result).to eq "SELECT * FROM users"
    end
  end
end
