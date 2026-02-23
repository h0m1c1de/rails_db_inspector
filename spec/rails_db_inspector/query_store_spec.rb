# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::QueryStore do
  # Use a fresh instance for each test (bypass singleton)
  let(:store) { described_class.clone.instance }

  let(:base_attrs) do
    {
      sql: "SELECT * FROM users",
      name: "User Load",
      binds: [],
      duration_ms: 1.5,
      connection_id: 42,
      timestamp: Time.now
    }
  end

  after { store.clear! }

  describe "#add" do
    it "stores a query and returns a Query struct" do
      query = store.add(**base_attrs)

      expect(query).to be_a(RailsDbInspector::QueryStore::Query)
      expect(query.sql).to eq "SELECT * FROM users"
      expect(query.name).to eq "User Load"
      expect(query.duration_ms).to eq 1.5
      expect(query.id).to be_a(String)
    end

    it "assigns a unique hex id" do
      q1 = store.add(**base_attrs)
      q2 = store.add(**base_attrs.merge(sql: "SELECT 1"))

      expect(q1.id).not_to eq q2.id
      expect(q1.id).to match(/\A[0-9a-f]{16}\z/)
    end

    it "converts duration_ms to float" do
      query = store.add(**base_attrs.merge(duration_ms: "2"))
      expect(query.duration_ms).to eq 2.0
    end
  end

  describe "#all" do
    it "returns all stored queries in insertion order" do
      q1 = store.add(**base_attrs.merge(sql: "SELECT 1"))
      q2 = store.add(**base_attrs.merge(sql: "SELECT 2"))

      all = store.all
      expect(all.map(&:sql)).to eq ["SELECT 1", "SELECT 2"]
    end

    it "returns a dup so external mutations don't affect the store" do
      store.add(**base_attrs)
      all = store.all
      all.clear

      expect(store.all.length).to eq 1
    end
  end

  describe "#find" do
    it "returns a query by id" do
      q = store.add(**base_attrs)
      expect(store.find(q.id)).to be q
    end

    it "returns nil for unknown id" do
      expect(store.find("nonexistent")).to be_nil
    end
  end

  describe "#clear!" do
    it "removes all queries" do
      store.add(**base_attrs)
      store.clear!

      expect(store.all).to be_empty
    end

    it "clears the id index too" do
      q = store.add(**base_attrs)
      store.clear!

      expect(store.find(q.id)).to be_nil
    end
  end

  describe "trimming" do
    it "trims oldest queries when exceeding max_queries" do
      RailsDbInspector.configure { |c| c.max_queries = 3 }

      q1 = store.add(**base_attrs.merge(sql: "SELECT 1"))
      q2 = store.add(**base_attrs.merge(sql: "SELECT 2"))
      q3 = store.add(**base_attrs.merge(sql: "SELECT 3"))
      q4 = store.add(**base_attrs.merge(sql: "SELECT 4"))

      all = store.all
      expect(all.length).to eq 3
      expect(all.map(&:sql)).to eq ["SELECT 2", "SELECT 3", "SELECT 4"]
      expect(store.find(q1.id)).to be_nil
    end

    it "does not trim when max_queries is 0 or negative" do
      RailsDbInspector.configure { |c| c.max_queries = 0 }

      5.times { |i| store.add(**base_attrs.merge(sql: "SELECT #{i}")) }
      expect(store.all.length).to eq 5
    end
  end

  describe "normalize_binds" do
    it "handles ActiveRecord-style bind objects with name and value_before_type_cast" do
      bind = double("bind", name: "id", value_before_type_cast: 42, type: double(type: :integer))
      q = store.add(**base_attrs.merge(binds: [bind]))

      expect(q.binds).to eq [{ name: "id", value: 42, type: :integer }]
    end

    it "handles bind with nil type" do
      bind = double("bind", name: "id", value_before_type_cast: 42, type: nil)
      q = store.add(**base_attrs.merge(binds: [bind]))

      expect(q.binds).to eq [{ name: "id", value: 42, type: nil }]
    end

    it "handles array-style binds [name, value]" do
      q = store.add(**base_attrs.merge(binds: [["id", 42]]))
      expect(q.binds).to eq [{ name: "id", value: 42, type: nil }]
    end

    it "handles raw values as fallback" do
      q = store.add(**base_attrs.merge(binds: [99]))
      expect(q.binds).to eq [{ name: nil, value: "99", type: nil }]
    end

    it "returns empty array for non-array binds" do
      q = store.add(**base_attrs.merge(binds: "not an array"))
      expect(q.binds).to eq []
    end

    it "returns empty array for nil binds" do
      q = store.add(**base_attrs.merge(binds: nil))
      expect(q.binds).to eq []
    end
  end
end
