# frozen_string_literal: true

require "spec_helper"
require_relative "../../app/helpers/rails_db_inspector/application_helper"

# Create a test class that includes the helper, exposing private methods for testing
class HelperTestHost
  include RailsDbInspector::ApplicationHelper
  public *RailsDbInspector::ApplicationHelper.private_instance_methods(false)
end

RSpec.describe RailsDbInspector::ApplicationHelper do
  let(:helper) { HelperTestHost.new }

  # Build query structs matching QueryStore::Query
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

  describe "#render_query_type" do
    before do
      # html_safe is already defined by ActiveSupport, no stub needed
    end

    it "detects SELECT queries" do
      query = build_query(sql: "SELECT * FROM users")
      result = helper.render_query_type(query)
      expect(result).to include("SELECT")
    end

    it "detects INSERT queries" do
      query = build_query(sql: "INSERT INTO users VALUES (1)")
      result = helper.render_query_type(query)
      expect(result).to include("INSERT")
    end

    it "detects UPDATE queries" do
      query = build_query(sql: "UPDATE users SET name = 'test'")
      result = helper.render_query_type(query)
      expect(result).to include("UPDATE")
    end

    it "detects DELETE queries" do
      query = build_query(sql: "DELETE FROM users WHERE id = 1")
      result = helper.render_query_type(query)
      expect(result).to include("DELETE")
    end

    it "detects CTE queries" do
      query = build_query(sql: "WITH active AS (SELECT * FROM users) SELECT * FROM active")
      result = helper.render_query_type(query)
      expect(result).to include("CTE")
    end

    it "labels unknown queries as OTHER" do
      query = build_query(sql: "SET timezone = 'UTC'")
      result = helper.render_query_type(query)
      expect(result).to include("OTHER")
    end

    it "adds JOIN complexity hint" do
      query = build_query(sql: "SELECT * FROM users join posts on users.id = posts.user_id")
      result = helper.render_query_type(query)
      expect(result).to include("JOIN")
    end

    it "adds SUBQUERY complexity hint" do
      query = build_query(sql: "SELECT * FROM users WHERE id IN (select id from admins)")
      result = helper.render_query_type(query)
      expect(result).to include("SUBQUERY")
    end

    it "adds AGGREGATE complexity hint" do
      query = build_query(sql: "SELECT count(*) FROM users GROUP BY status")
      result = helper.render_query_type(query)
      expect(result).to include("AGGREGATE")
    end

    it "adds ORDER BY complexity hint" do
      query = build_query(sql: "SELECT * FROM users order by name")
      result = helper.render_query_type(query)
      expect(result).to include("ORDER BY")
    end

    it "adds WINDOW complexity hint" do
      query = build_query(sql: "SELECT *, row_number() over (partition by status) FROM users")
      result = helper.render_query_type(query)
      expect(result).to include("WINDOW")
    end
  end

  describe "#group_queries_by_action" do

    it "returns empty array for empty queries" do
      expect(helper.group_queries_by_action([])).to eq []
    end

    it "groups queries by controller action" do
      t = Time.now
      queries = [
        build_query(sql: "/* controller='users', action='index' */ SELECT * FROM users", timestamp: t),
        build_query(sql: "/* controller='users', action='index' */ SELECT * FROM posts", timestamp: t + 0.1)
      ]

      groups = helper.group_queries_by_action(queries)
      expect(groups.length).to eq 1
      expect(groups.first[:queries].length).to eq 2
    end

    it "starts new group when controller action changes" do
      t = Time.now
      queries = [
        build_query(sql: "/* controller='users', action='index' */ SELECT * FROM users", timestamp: t),
        build_query(sql: "/* controller='posts', action='show' */ SELECT * FROM posts", timestamp: t + 0.1)
      ]

      groups = helper.group_queries_by_action(queries)
      expect(groups.length).to eq 2
    end

    it "starts new group when time gap is too large" do
      t = Time.now
      queries = [
        build_query(name: "User Load", timestamp: t),
        build_query(name: "User Load", timestamp: t + 15) # 15 seconds gap
      ]

      groups = helper.group_queries_by_action(queries)
      expect(groups.length).to eq 2
    end
  end

  describe "#detect_n_plus_one" do

    it "returns empty array for fewer than 3 queries" do
      queries = [build_query, build_query]
      expect(helper.detect_n_plus_one(queries)).to eq []
    end

    it "detects N+1 patterns (same query 3+ times)" do
      queries = 5.times.map do
        build_query(sql: "SELECT * FROM posts WHERE user_id = 1", name: "Post Load")
      end

      n_plus_ones = helper.detect_n_plus_one(queries)
      expect(n_plus_ones.length).to eq 1
      expect(n_plus_ones.first[:count]).to eq 5
      expect(n_plus_ones.first[:table]).to eq "posts"
    end

    it "ignores queries that appear fewer than 3 times" do
      queries = [
        build_query(sql: "SELECT * FROM users WHERE id = 1"),
        build_query(sql: "SELECT * FROM users WHERE id = 2"),
        build_query(sql: "SELECT * FROM posts") # different query
      ]

      n_plus_ones = helper.detect_n_plus_one(queries)
      expect(n_plus_ones).to be_empty
    end

    it "ignores BEGIN/COMMIT/ROLLBACK/SET/SHOW queries" do
      queries = 5.times.map { build_query(sql: "BEGIN") }
      n_plus_ones = helper.detect_n_plus_one(queries)
      expect(n_plus_ones).to be_empty
    end

    it "normalizes numeric literals when detecting patterns" do
      queries = [
        build_query(sql: "SELECT * FROM posts WHERE user_id = 1"),
        build_query(sql: "SELECT * FROM posts WHERE user_id = 2"),
        build_query(sql: "SELECT * FROM posts WHERE user_id = 3")
      ]

      n_plus_ones = helper.detect_n_plus_one(queries)
      expect(n_plus_ones.length).to eq 1
    end

    it "calculates total duration for N+1 groups" do
      queries = 3.times.map do |i|
        build_query(sql: "SELECT * FROM posts WHERE user_id = #{i}", duration_ms: 2.0)
      end

      n_plus_ones = helper.detect_n_plus_one(queries)
      expect(n_plus_ones.first[:total_duration_ms]).to eq 6.0
    end

    it "sorts by count descending" do
      queries = []
      3.times { queries << build_query(sql: "SELECT * FROM posts WHERE id = 1") }
      5.times { queries << build_query(sql: "SELECT * FROM comments WHERE post_id = 1") }

      n_plus_ones = helper.detect_n_plus_one(queries)
      expect(n_plus_ones.first[:count]).to eq 5
      expect(n_plus_ones.last[:count]).to eq 3
    end
  end

  describe "#schema_to_json" do
    it "serializes schema hash to JSON" do
      schema = {
        "users" => {
          columns: [{ name: "id", type: "integer", nullable: false, default: nil }],
          indexes: [{ name: "idx_users_pk", columns: ["id"], unique: true }],
          foreign_keys: [{ column: "org_id", to_table: "orgs", primary_key: "id" }],
          primary_key: "id",
          row_count: 100,
          associations: [{ name: "posts", macro: "has_many", target_table: "posts", foreign_key: "user_id", through: nil }],
          missing_indexes: ["org_id"],
          polymorphic_columns: [{ name: "taggable", type_column: "taggable_type", id_column: "taggable_id" }]
        }
      }

      json = helper.schema_to_json(schema)
      parsed = JSON.parse(json)

      expect(parsed["users"]["columns"].first["name"]).to eq "id"
      expect(parsed["users"]["indexes"].first["unique"]).to be true
      expect(parsed["users"]["missing_indexes"]).to eq ["org_id"]
      expect(parsed["users"]["polymorphic_columns"].first["name"]).to eq "taggable"
    end
  end

  describe "#relationships_to_json" do
    it "serializes relationships array to JSON" do
      rels = [
        { from_table: "posts", from_column: "user_id", to_table: "users", to_column: "id", type: :foreign_key }
      ]

      json = helper.relationships_to_json(rels)
      parsed = JSON.parse(json)

      expect(parsed.first["type"]).to eq "foreign_key"
      expect(parsed.first["from_table"]).to eq "posts"
    end
  end
end
