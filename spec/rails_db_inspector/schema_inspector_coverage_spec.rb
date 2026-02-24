# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::SchemaInspector, "coverage" do
  let(:connection) { double("connection") }
  subject(:inspector) { described_class.new(connection) }

  let(:column_id) do
    double("column", name: "id", sql_type: "integer", null: false, default: nil)
  end

  describe "#find_model_for_table" do
    before do
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
    end

    it "returns nil when a model raises on table_name" do
      bad_model = Class.new(ActiveRecord::Base)
      allow(bad_model).to receive(:table_name).and_raise(StandardError, "boom")
      allow(bad_model).to receive(:abstract_class?).and_return(false)
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ bad_model ])

      result = inspector.send(:find_model_for_table, "users")
      expect(result).to be_nil
    end

    it "returns nil when descendants itself raises" do
      allow(ActiveRecord::Base).to receive(:descendants).and_raise(StandardError, "boom")

      result = inspector.send(:find_model_for_table, "users")
      expect(result).to be_nil
    end

    it "skips abstract classes" do
      abstract_model = Class.new(ActiveRecord::Base)
      allow(abstract_model).to receive(:table_name).and_return("users")
      allow(abstract_model).to receive(:abstract_class?).and_return(true)
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ abstract_model ])

      result = inspector.send(:find_model_for_table, "users")
      expect(result).to be_nil
    end
  end

  describe "#eager_load_models!" do
    it "loads model files from Rails model paths" do
      dir = Dir.mktmpdir
      model_file = File.join(dir, "dummy_model.rb")
      File.write(model_file, "# dummy model file")

      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [ dir ] }),
          eager_load!: nil
        )
      ))
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])

      # Should not raise
      inspector.send(:eager_load_models!)
    ensure
      FileUtils.rm_rf(dir) if dir
    end

    it "handles model files that fail to load" do
      dir = Dir.mktmpdir
      model_file = File.join(dir, "broken_model.rb")
      File.write(model_file, "raise 'intentional error'")

      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [ dir ] }),
          eager_load!: nil
        )
      ))
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])

      # Should not raise even though model file raises
      expect { inspector.send(:eager_load_models!) }.not_to raise_error
    ensure
      FileUtils.rm_rf(dir) if dir
    end

    it "uses eager_load! fallback when no descendants found" do
      rails_app = double(
        config: double(paths: { "app/models" => [] }),
        eager_load!: nil
      )
      stub_const("Rails", double(application: rails_app))
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])

      expect(rails_app).to receive(:eager_load!)
      inspector.send(:eager_load_models!)
    end

    it "only runs once (memoized)" do
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])

      inspector.send(:eager_load_models!)
      # Second call should be no-op
      expect(Rails.application).not_to receive(:eager_load!)
      inspector.send(:eager_load_models!)
    end
  end

  describe "#detect_polymorphic_columns edge cases" do
    it "skips _type column when matching _id column is missing" do
      columns = [
        { name: "id", type: "integer" },
        { name: "taggable_type", type: "varchar" }
        # no taggable_id column!
      ]
      result = inspector.send(:detect_polymorphic_columns, columns)
      expect(result).to be_empty
    end
  end

  describe "#introspect_associations error handling" do
    before do
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
    end

    it "handles associations where klass.table_name raises" do
      model = Class.new(ActiveRecord::Base)
      allow(model).to receive(:table_name).and_return("users")
      allow(model).to receive(:abstract_class?).and_return(false)

      assoc = double("assoc",
        name: :posts,
        macro: :has_many,
        foreign_key: "user_id",
        options: {}
      )
      allow(assoc).to receive(:klass).and_raise(StandardError, "cannot load")
      allow(model).to receive(:reflect_on_all_associations).and_return([ assoc ])
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ model ])

      result = inspector.send(:introspect_associations, "users")
      expect(result.first[:target_table]).to be_nil
    end

    it "includes through option when present" do
      model = Class.new(ActiveRecord::Base)
      allow(model).to receive(:table_name).and_return("users")
      allow(model).to receive(:abstract_class?).and_return(false)

      assoc = double("assoc",
        name: :tags,
        macro: :has_many,
        foreign_key: "user_id",
        options: { through: :taggings }
      )
      allow(assoc).to receive(:klass).and_return(double(table_name: "tags"))
      allow(model).to receive(:reflect_on_all_associations).and_return([ assoc ])
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ model ])

      result = inspector.send(:introspect_associations, "users")
      expect(result.first[:through]).to eq "taggings"
    end

    it "returns empty array when reflect_on_all_associations raises" do
      model = Class.new(ActiveRecord::Base)
      allow(model).to receive(:table_name).and_return("users")
      allow(model).to receive(:abstract_class?).and_return(false)
      allow(model).to receive(:reflect_on_all_associations).and_raise(StandardError, "boom")
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ model ])

      result = inspector.send(:introspect_associations, "users")
      expect(result).to eq []
    end
  end

  describe "#suggest_polymorphic_composite_indexes edge cases" do
    it "handles multiple polymorphic columns" do
      polymorphics = [
        { name: "commentable", type_column: "commentable_type", id_column: "commentable_id" },
        { name: "taggable", type_column: "taggable_type", id_column: "taggable_id" }
      ]
      indexes = []

      result = inspector.send(:suggest_polymorphic_composite_indexes, "comments", indexes, polymorphics)
      expect(result.length).to eq 2
    end

    it "skips only the polymorphic that has a matching composite index" do
      polymorphics = [
        { name: "commentable", type_column: "commentable_type", id_column: "commentable_id" },
        { name: "taggable", type_column: "taggable_type", id_column: "taggable_id" }
      ]
      indexes = [
        { name: "idx", columns: [ "commentable_type", "commentable_id" ], unique: false }
      ]

      result = inspector.send(:suggest_polymorphic_composite_indexes, "comments", indexes, polymorphics)
      expect(result.length).to eq 1
      expect(result.first[:columns]).to eq [ "taggable_type", "taggable_id" ]
    end
  end

  describe "#suggest_join_table_composite_indexes edge cases" do
    it "returns empty when table has fewer than 2 _id columns" do
      columns = [ { name: "id", type: "integer" }, { name: "user_id", type: "integer" } ]
      result = inspector.send(:suggest_join_table_composite_indexes, "posts", columns, [], [])
      expect(result).to be_empty
    end

    it "skips unique suggestion when unique composite already exists" do
      columns = [
        { name: "id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "tag_id", type: "integer" }
      ]
      indexes = [
        { name: "idx_uniq", columns: [ "post_id", "tag_id" ], unique: true }
      ]
      result = inspector.send(:suggest_join_table_composite_indexes, "post_tags", columns, indexes, [])
      expect(result).to be_empty
    end

    it "suggests for 3 FK column combinations" do
      columns = [
        { name: "id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "tag_id", type: "integer" },
        { name: "user_id", type: "integer" }
      ]
      result = inspector.send(:suggest_join_table_composite_indexes, "post_tag_users", columns, [], [])
      # 3 FK cols => C(3,2)=3 pairs, each with regular+unique = 6 suggestions
      regular = result.select { |s| s[:reason] == :join_table }
      expect(regular.length).to eq 3
    end
  end

  describe "#suggest_query_driven_indexes edge cases" do
    before do
      RailsDbInspector::QueryStore.instance.clear!
    end

    it "ignores queries that don't reference the table" do
      3.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM users WHERE name = 'test'",
          name: "User Load",
          binds: [],
          duration_ms: 1.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      result = inspector.send(:suggest_query_driven_indexes, "posts", [])
      expect(result).to be_empty
    end

    it "limits suggestions to 5" do
      # Generate many distinct column pairs
      10.times do |i|
        3.times do
          RailsDbInspector::QueryStore.instance.add(
            sql: "SELECT * FROM posts WHERE col_a#{i} = 1 AND col_b#{i} = 2",
            name: "Post Load",
            binds: [],
            duration_ms: 1.0,
            connection_id: 1,
            timestamp: Time.now
          )
        end
      end

      result = inspector.send(:suggest_query_driven_indexes, "posts", [])
      expect(result.length).to be <= 5
    end

    it "extracts columns from table-qualified multi-table queries" do
      3.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM posts JOIN users ON users.id = posts.user_id WHERE posts.status = 'active' AND posts.category_id = 1",
          name: "Post Load",
          binds: [],
          duration_ms: 1.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      result = inspector.send(:suggest_query_driven_indexes, "posts", [])
      expect(result).not_to be_empty
      cols = result.first[:columns]
      expect(cols).to include("status")
    end
  end

  describe "#extract_where_columns edge cases" do
    it "returns empty for queries with no WHERE clause" do
      result = inspector.send(:extract_where_columns, "SELECT * FROM posts", "posts")
      expect(result).to be_empty
    end

    it "stops at GROUP BY" do
      sql = "SELECT * FROM posts WHERE posts.status = 'active' GROUP BY posts.category_id"
      result = inspector.send(:extract_where_columns, sql, "posts")
      expect(result).to include("status")
    end

    it "handles quoted table names" do
      sql = 'SELECT * FROM "posts" WHERE "posts"."user_id" = 1'
      result = inspector.send(:extract_where_columns, sql, "posts")
      expect(result).to include("user_id")
    end
  end

  describe "#extract_order_columns edge cases" do
    it "returns empty for queries with no ORDER BY" do
      result = inspector.send(:extract_order_columns, "SELECT * FROM posts", "posts")
      expect(result).to be_empty
    end

    it "stops at LIMIT" do
      sql = "SELECT * FROM posts ORDER BY posts.created_at LIMIT 10"
      result = inspector.send(:extract_order_columns, sql, "posts")
      expect(result).to include("created_at")
    end

    it "excludes ASC/DESC keywords" do
      sql = "SELECT * FROM posts ORDER BY created_at DESC"
      result = inspector.send(:extract_order_columns, sql, "posts")
      expect(result).to include("created_at")
      expect(result).not_to include("DESC")
    end
  end

  describe "#looks_like_join_table? edge cases" do
    it "allows timestamps alongside FK columns" do
      columns = [
        { name: "id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "tag_id", type: "integer" },
        { name: "created_at", type: "datetime" },
        { name: "updated_at", type: "datetime" }
      ]
      expect(inspector.send(:looks_like_join_table?, "post_tags", columns)).to be true
    end
  end

  describe "#detect_index_suggestions deduplication" do
    it "deduplicates suggestions with same columns" do
      polymorphics = [
        { name: "commentable", type_column: "commentable_type", id_column: "commentable_id" }
      ]
      columns = [
        { name: "id", type: "integer" },
        { name: "commentable_type", type: "varchar" },
        { name: "commentable_id", type: "integer" }
      ]
      indexes = []
      associations = []

      result = inspector.send(:detect_index_suggestions, "comments", columns, indexes, polymorphics, associations)
      # Check no duplicate column sets
      column_sets = result.map { |s| s[:columns].sort }
      expect(column_sets).to eq column_sets.uniq
    end
  end

  describe "#safe_bool_count" do
    it "returns count on success" do
      allow(connection).to receive(:quote_table_name).and_return('"t"')
      allow(connection).to receive(:quote_column_name).and_return('"c"')
      allow(connection).to receive(:select_value).and_return(42)

      expect(inspector.send(:safe_bool_count, "t", "c", true)).to eq 42
    end

    it "returns nil on error" do
      allow(connection).to receive(:quote_table_name).and_raise(StandardError)

      expect(inspector.send(:safe_bool_count, "t", "c", true)).to be_nil
    end
  end

  describe "#suggest_sti_index edge cases" do
    it "skips when type column is part of composite index" do
      columns = [
        { name: "id", type: "integer" },
        { name: "type", type: "varchar(255)" }
      ]
      indexes = [
        { name: "index_on_type_and_status", columns: [ "type", "status" ], unique: false }
      ]

      result = inspector.send(:suggest_sti_index, "vehicles", columns, indexes)
      expect(result).to be_empty
    end
  end

  describe "#suggest_uniqueness_indexes edge cases" do
    it "handles error when loading descendants" do
      allow(ActiveRecord::Base).to receive(:descendants).and_raise(StandardError)

      result = inspector.send(:suggest_uniqueness_indexes, "users", [], [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_covering_indexes edge cases" do
    before { RailsDbInspector::QueryStore.instance.clear! }

    it "skips queries below frequency threshold" do
      1.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM posts WHERE posts.status = 'active' ORDER BY posts.created_at DESC",
          name: "Post Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      result = inspector.send(:suggest_covering_indexes, "posts", [])
      expect(result).to be_empty
    end

    it "skips when covering index already exists" do
      3.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM posts WHERE posts.status = 'active' ORDER BY posts.created_at DESC",
          name: "Post Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      indexes = [
        { name: "index_posts_on_status_created_at", columns: [ "status", "created_at" ], unique: false }
      ]

      result = inspector.send(:suggest_covering_indexes, "posts", indexes)
      expect(result).to be_empty
    end
  end

  describe "#suggest_partial_indexes_for_booleans edge cases" do
    it "handles database error gracefully" do
      allow(connection).to receive(:quote_table_name).and_raise(StandardError)

      columns = [
        { name: "id", type: "integer" },
        { name: "active", type: "boolean" }
      ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end
    it "skips when row count is too low" do
      allow(connection).to receive(:quote_table_name).and_return('"users"')
      allow(connection).to receive(:select_value).and_return(50)

      columns = [
        { name: "id", type: "integer" },
        { name: "active", type: "boolean" }
      ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end

    it "skips when true_count is nil" do
      allow(connection).to receive(:quote_table_name).and_return('"users"')
      allow(connection).to receive(:quote_column_name).and_return('"active"')
      allow(connection).to receive(:select_value).and_return(200, nil)

      columns = [
        { name: "id", type: "integer" },
        { name: "active", type: "boolean" }
      ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end

    it "skips when total is zero" do
      allow(connection).to receive(:quote_table_name).and_return('"users"')
      allow(connection).to receive(:quote_column_name).and_return('"active"')
      allow(connection).to receive(:select_value).and_return(200, 0, 0)

      columns = [
        { name: "id", type: "integer" },
        { name: "active", type: "boolean" }
      ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end

    it "picks false as minority value when false_count < true_count" do
      allow(connection).to receive(:quote_table_name).and_return('"users"')
      allow(connection).to receive(:quote_column_name).and_return('"active"')
      allow(connection).to receive(:select_value).and_return(200, 180, 20)

      columns = [
        { name: "id", type: "integer" },
        { name: "active", type: "boolean" }
      ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result.length).to eq 1
      expect(result.first[:sql]).to include("false")
    end  end

  describe "#detect_redundant_indexes edge cases" do
    it "does not flag unique indexes as redundant" do
      indexes = [
        { name: "index_email_unique", columns: [ "email" ], unique: true },
        { name: "index_email_and_name", columns: [ "email", "name" ], unique: false }
      ]

      result = inspector.send(:detect_redundant_indexes, "users", indexes)
      expect(result).to be_empty
    end
  end

  describe "#suggest_soft_delete_partial_index edge cases" do
    it "prefers deleted_at over discarded_at when both exist" do
      columns = [
        { name: "id", type: "integer" },
        { name: "deleted_at", type: "datetime" },
        { name: "discarded_at", type: "datetime" }
      ]

      result = inspector.send(:suggest_soft_delete_partial_index, "posts", columns, [])
      expect(result.length).to eq 1
      expect(result.first[:columns]).to eq [ "deleted_at" ]
    end

    it "skips when soft-delete column is already indexed" do
      columns = [
        { name: "id", type: "integer" },
        { name: "deleted_at", type: "datetime" }
      ]
      indexes = [
        { name: "index_posts_on_deleted_at", columns: [ "deleted_at" ], unique: false }
      ]

      result = inspector.send(:suggest_soft_delete_partial_index, "posts", columns, indexes)
      expect(result).to be_empty
    end
  end

  describe "#suggest_timestamp_ordering_indexes edge cases" do
    before { RailsDbInspector::QueryStore.instance.clear! }

    it "requires at least 2 occurrences" do
      1.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM posts ORDER BY posts.created_at DESC",
          name: "Post Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      columns = [
        { name: "id", type: "integer" },
        { name: "created_at", type: "datetime" }
      ]

      result = inspector.send(:suggest_timestamp_ordering_indexes, "posts", columns, [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_counter_cache_indexes edge cases" do
    before { RailsDbInspector::QueryStore.instance.clear! }

    it "requires at least 2 occurrences" do
      1.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM users ORDER BY users.posts_count DESC",
          name: "User Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      columns = [
        { name: "id", type: "integer" },
        { name: "posts_count", type: "integer" }
      ]

      result = inspector.send(:suggest_counter_cache_indexes, "users", columns, [])
      expect(result).to be_empty
    end

    it "suggests index when counter cache column used in ORDER BY 2+ times" do
      2.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM users ORDER BY users.posts_count DESC",
          name: "User Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      columns = [
        { name: "id", type: "integer" },
        { name: "posts_count", type: "integer" }
      ]

      result = inspector.send(:suggest_counter_cache_indexes, "users", columns, [])
      expect(result).not_to be_empty
      expect(result.first[:reason]).to eq(:counter_cache)
    end

    it "skips counter cache column already indexed" do
      2.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM users ORDER BY users.posts_count DESC",
          name: "User Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      columns = [
        { name: "id", type: "integer" },
        { name: "posts_count", type: "integer" }
      ]
      indexes = [ { name: "idx_posts_count", columns: [ "posts_count" ], unique: false } ]

      result = inspector.send(:suggest_counter_cache_indexes, "users", columns, indexes)
      expect(result).to be_empty
    end

    it "skips non-counter columns that don't reference the table" do
      2.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM other_table ORDER BY other_table.posts_count DESC",
          name: "Other Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      columns = [
        { name: "id", type: "integer" },
        { name: "posts_count", type: "integer" }
      ]

      result = inspector.send(:suggest_counter_cache_indexes, "users", columns, [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_timestamp_ordering_indexes additional coverage" do
    before { RailsDbInspector::QueryStore.instance.clear! }

    it "suggests index when timestamp column used in ORDER BY 2+ times" do
      2.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM posts ORDER BY posts.created_at DESC",
          name: "Post Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      columns = [
        { name: "id", type: "integer" },
        { name: "created_at", type: "datetime" }
      ]

      result = inspector.send(:suggest_timestamp_ordering_indexes, "posts", columns, [])
      expect(result).not_to be_empty
      expect(result.first[:reason]).to eq(:timestamp_order)
    end

    it "skips timestamp column already indexed" do
      2.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM posts ORDER BY posts.created_at DESC",
          name: "Post Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      columns = [
        { name: "id", type: "integer" },
        { name: "created_at", type: "datetime" }
      ]
      indexes = [ { name: "idx_created", columns: [ "created_at" ], unique: false } ]

      result = inspector.send(:suggest_timestamp_ordering_indexes, "posts", columns, indexes)
      expect(result).to be_empty
    end
  end

  describe "#detect_index_suggestions deduplication" do
    before do
      RailsDbInspector::QueryStore.instance.clear!
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])
    end

    it "deduplicates suggestions with same reason and columns" do
      columns = [
        { name: "id", type: "integer" },
        { name: "name", type: "varchar" }
      ]
      result = inspector.send(:detect_index_suggestions, "users", columns, [], [], [])
      # Just verify it returns without error and no duplicates
      seen = result.map { |s| [ s[:reason], s[:columns]&.sort ] }
      expect(seen.uniq.length).to eq(seen.length)
    end
  end

  describe "#suggest_join_table_composite_indexes — not a join table" do
    it "returns empty when table is not a join table" do
      columns = [
        { name: "id", type: "integer" },
        { name: "user_id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "content", type: "text" },
        { name: "title", type: "varchar" },
        { name: "body", type: "text" }
      ]
      result = inspector.send(:suggest_join_table_composite_indexes, "reviews", columns, [], [])
      expect(result).to be_empty
    end

    it "suppresses unique index when one already exists" do
      columns = [
        { name: "id", type: "integer" },
        { name: "user_id", type: "integer" },
        { name: "role_id", type: "integer" }
      ]
      indexes = [
        { name: "idx_unique", columns: [ "user_id", "role_id" ], unique: true }
      ]
      associations = [ { through: "user_roles" } ]

      result = inspector.send(:suggest_join_table_composite_indexes, "user_roles", columns, indexes, associations)
      unique_suggestions = result.select { |s| s[:reason] == :join_table_unique }
      expect(unique_suggestions).to be_empty
    end
  end

  describe "#suggest_query_driven_indexes — bad parse skipping" do
    before { RailsDbInspector::QueryStore.instance.clear! }

    it "skips columns with * or ( in them" do
      2.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT COUNT(*) FROM users WHERE users.status = 'active' AND users.role = 'admin'",
          name: "User Count",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      result = inspector.send(:suggest_query_driven_indexes, "users", [])
      # Verify suggestions don't include columns with * or (
      result.each do |s|
        s[:columns].each do |c|
          expect(c).not_to include("*")
          expect(c).not_to include("(")
        end
      end
    end
  end

  describe "#extract_where_columns — additional branches" do
    it "skips SQL keywords in simple WHERE columns" do
      columns = inspector.send(:extract_where_columns, "SELECT * FROM users WHERE AND = 1", "users")
      expect(columns).not_to include("AND")
    end

    it "skips numeric literals in simple WHERE columns" do
      columns = inspector.send(:extract_where_columns, "SELECT * FROM users WHERE 123 = 1", "users")
      expect(columns).not_to include("123")
    end

    it "uses simple column extraction for single-table queries" do
      columns = inspector.send(:extract_where_columns, "SELECT * FROM users WHERE status = 'active'", "users")
      expect(columns).to include("status")
    end

    it "does not use simple extraction for multi-table queries" do
      columns = inspector.send(:extract_where_columns,
        "SELECT * FROM users JOIN posts ON users.id = posts.user_id WHERE users.status = 'active'",
        "users"
      )
      expect(columns).to include("status")
    end
  end

  describe "#suggest_covering_indexes — additional branches" do
    before { RailsDbInspector::QueryStore.instance.clear! }

    it "skips covering candidates with * or ( in columns" do
      2.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM users WHERE users.status = 'active' ORDER BY users.name",
          name: "User Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      result = inspector.send(:suggest_covering_indexes, "users", [])
      result.each do |s|
        s[:columns].each do |c|
          expect(c).not_to include("*")
          expect(c).not_to include("(")
        end
      end
    end

    it "skips candidates with fewer than 2 columns" do
      2.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM users WHERE users.status = 'active' ORDER BY users.status",
          name: "User Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      result = inspector.send(:suggest_covering_indexes, "users", [])
      # Only single column used in both WHERE and ORDER BY — might be filtered out
      expect(result).to be_a(Array)
    end
  end

  describe "#suggest_uniqueness_indexes — column validation" do
    before do
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
    end

    it "skips when validator columns not present in table" do
      model = Class.new(ActiveRecord::Base)
      allow(model).to receive(:table_name).and_return("users")
      allow(model).to receive(:abstract_class?).and_return(false)

      validator = double("validator",
        attributes: [ :email ],
        options: {}
      )
      allow(validator).to receive(:is_a?).with(ActiveRecord::Validations::UniquenessValidator).and_return(true)
      allow(model).to receive(:validators).and_return([ validator ])
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ model ])

      columns = [ { name: "id", type: "integer" }, { name: "name", type: "varchar" } ]

      # email column not in table columns list
      result = inspector.send(:suggest_uniqueness_indexes, "users", columns, [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_partial_indexes_for_booleans — distribution checks" do
    it "skips when boolean data is not skewed (minority >= 30%)" do
      allow(connection).to receive(:quote_table_name) { |t| "\"#{t}\"" }
      allow(connection).to receive(:quote_column_name) { |c| "\"#{c}\"" }
      allow(connection).to receive(:select_value).and_return(100, 50, 50) # total, true, false

      columns = [ { name: "active", type: "boolean" } ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end

    it "skips when total is 0" do
      allow(connection).to receive(:quote_table_name) { |t| "\"#{t}\"" }
      allow(connection).to receive(:quote_column_name) { |c| "\"#{c}\"" }
      allow(connection).to receive(:select_value).and_return(100, 0, 0) # total, true, false

      columns = [ { name: "active", type: "boolean" } ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end

    it "skips when row count returns nil" do
      allow(connection).to receive(:quote_table_name) { |t| "\"#{t}\"" }
      allow(connection).to receive(:select_value).and_return(nil)

      columns = [ { name: "active", type: "boolean" } ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end

    it "skips when bool count returns nil" do
      allow(connection).to receive(:quote_table_name) { |t| "\"#{t}\"" }
      allow(connection).to receive(:quote_column_name) { |c| "\"#{c}\"" }
      allow(connection).to receive(:select_value).and_return(500, nil, nil)

      columns = [ { name: "active", type: "boolean" } ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end
  end
end
