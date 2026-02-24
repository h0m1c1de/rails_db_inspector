# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::SchemaInspector do
  let(:connection) { double("connection") }
  subject(:inspector) { described_class.new(connection) }

  let(:column_id) do
    double("column", name: "id", sql_type: "integer", null: false, default: nil)
  end

  let(:column_name) do
    double("column", name: "name", sql_type: "varchar(255)", null: true, default: nil)
  end

  let(:column_user_id) do
    double("column", name: "user_id", sql_type: "integer", null: false, default: nil)
  end

  let(:column_commentable_type) do
    double("column", name: "commentable_type", sql_type: "varchar(255)", null: false, default: nil)
  end

  let(:column_commentable_id) do
    double("column", name: "commentable_id", sql_type: "integer", null: false, default: nil)
  end

  let(:index) do
    double("index", name: "index_posts_on_user_id", columns: [ "user_id" ], unique: false)
  end

  let(:foreign_key) do
    double("fk", column: "user_id", to_table: "users", primary_key: "id", name: "fk_posts_user")
  end

  describe "#introspect" do
    before do
      allow(connection).to receive(:tables).and_return([ "users", "posts", "schema_migrations", "ar_internal_metadata" ])
      allow(connection).to receive(:columns).with("users").and_return([ column_id, column_name ])
      allow(connection).to receive(:columns).with("posts").and_return([ column_id, column_user_id ])
      allow(connection).to receive(:indexes).with("users").and_return([])
      allow(connection).to receive(:indexes).with("posts").and_return([ index ])
      allow(connection).to receive(:respond_to?).with(:foreign_keys).and_return(true)
      allow(connection).to receive(:foreign_keys).with("users").and_return([])
      allow(connection).to receive(:foreign_keys).with("posts").and_return([ foreign_key ])
      allow(connection).to receive(:primary_key).with("users").and_return("id")
      allow(connection).to receive(:primary_key).with("posts").and_return("id")
      allow(connection).to receive(:quote_table_name) { |t| "\"#{t}\"" }
      allow(connection).to receive(:select_value).and_return(10)

      # Stub ActiveRecord model lookup
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
    end

    it "filters out schema_migrations and ar_internal_metadata" do
      schema = inspector.introspect
      expect(schema.keys).to match_array([ "posts", "users" ])
    end

    it "includes columns for each table" do
      schema = inspector.introspect
      user_cols = schema["users"][:columns]

      expect(user_cols.length).to eq 2
      expect(user_cols.first[:name]).to eq "id"
      expect(user_cols.first[:type]).to eq "integer"
      expect(user_cols.first[:nullable]).to be false
    end

    it "includes indexes for each table" do
      schema = inspector.introspect
      post_indexes = schema["posts"][:indexes]

      expect(post_indexes.length).to eq 1
      expect(post_indexes.first[:name]).to eq "index_posts_on_user_id"
      expect(post_indexes.first[:columns]).to eq [ "user_id" ]
      expect(post_indexes.first[:unique]).to be false
    end

    it "includes foreign keys" do
      schema = inspector.introspect
      post_fks = schema["posts"][:foreign_keys]

      expect(post_fks.length).to eq 1
      expect(post_fks.first[:column]).to eq "user_id"
      expect(post_fks.first[:to_table]).to eq "users"
    end

    it "includes primary key" do
      schema = inspector.introspect
      expect(schema["users"][:primary_key]).to eq "id"
    end

    it "includes row count" do
      schema = inspector.introspect
      expect(schema["users"][:row_count]).to eq 10
    end

    it "detects missing indexes on _id columns" do
      # users has no index on user_id columns, but has no _id columns either
      # posts has user_id with an index, so no missing indexes
      schema = inspector.introspect
      expect(schema["posts"][:missing_indexes]).to eq []
    end

    it "detects missing indexes when _id column has no index" do
      allow(connection).to receive(:indexes).with("posts").and_return([])

      schema = inspector.introspect
      expect(schema["posts"][:missing_indexes]).to eq [ "user_id" ]
    end

    it "includes index_suggestions key in introspect results" do
      schema = inspector.introspect
      expect(schema["posts"]).to have_key(:index_suggestions)
      expect(schema["posts"][:index_suggestions]).to be_an(Array)
    end
  end

  describe "#introspect - foreign_keys not supported" do
    before do
      allow(connection).to receive(:tables).and_return([ "users" ])
      allow(connection).to receive(:columns).with("users").and_return([ column_id ])
      allow(connection).to receive(:indexes).with("users").and_return([])
      allow(connection).to receive(:respond_to?).with(:foreign_keys).and_return(false)
      allow(connection).to receive(:primary_key).with("users").and_return("id")
      allow(connection).to receive(:quote_table_name).and_return("\"users\"")
      allow(connection).to receive(:select_value).and_return(5)
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
    end

    it "returns empty foreign keys when not supported" do
      schema = inspector.introspect
      expect(schema["users"][:foreign_keys]).to eq []
    end
  end

  describe "#introspect - safe_row_count error handling" do
    before do
      allow(connection).to receive(:tables).and_return([ "users" ])
      allow(connection).to receive(:columns).with("users").and_return([ column_id ])
      allow(connection).to receive(:indexes).with("users").and_return([])
      allow(connection).to receive(:respond_to?).with(:foreign_keys).and_return(false)
      allow(connection).to receive(:primary_key).with("users").and_return("id")
      allow(connection).to receive(:quote_table_name).and_return("\"users\"")
      allow(connection).to receive(:select_value).and_raise(StandardError, "connection lost")
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
    end

    it "returns nil when counting fails" do
      schema = inspector.introspect
      expect(schema["users"][:row_count]).to be_nil
    end
  end

  describe "polymorphic columns detection" do
    before do
      allow(connection).to receive(:tables).and_return([ "comments" ])
      allow(connection).to receive(:columns).with("comments")
        .and_return([ column_id, column_commentable_type, column_commentable_id ])
      allow(connection).to receive(:indexes).with("comments").and_return([])
      allow(connection).to receive(:respond_to?).with(:foreign_keys).and_return(false)
      allow(connection).to receive(:primary_key).with("comments").and_return("id")
      allow(connection).to receive(:quote_table_name).and_return("\"comments\"")
      allow(connection).to receive(:select_value).and_return(0)
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
    end

    it "detects polymorphic column pairs" do
      schema = inspector.introspect
      poly = schema["comments"][:polymorphic_columns]

      expect(poly.length).to eq 1
      expect(poly.first[:name]).to eq "commentable"
      expect(poly.first[:type_column]).to eq "commentable_type"
      expect(poly.first[:id_column]).to eq "commentable_id"
    end
  end

  describe "#relationships" do
    before do
      allow(connection).to receive(:tables).and_return([ "users", "posts" ])
      allow(connection).to receive(:respond_to?).with(:foreign_keys).and_return(true)
      allow(connection).to receive(:foreign_keys).with("users").and_return([])
      allow(connection).to receive(:foreign_keys).with("posts").and_return([ foreign_key ])
      allow(connection).to receive(:columns).with("users").and_return([ column_id ])
      allow(connection).to receive(:columns).with("posts").and_return([ column_id, column_user_id ])
    end

    it "includes foreign key relationships" do
      rels = inspector.relationships
      fk_rels = rels.select { |r| r[:type] == :foreign_key }

      expect(fk_rels.length).to eq 1
      expect(fk_rels.first[:from_table]).to eq "posts"
      expect(fk_rels.first[:to_table]).to eq "users"
    end

    it "includes convention-based relationships for _id columns not covered by FK" do
      allow(connection).to receive(:foreign_keys).with("posts").and_return([])

      rels = inspector.relationships
      conv_rels = rels.select { |r| r[:type] == :convention }

      expect(conv_rels.length).to eq 1
      expect(conv_rels.first[:from_table]).to eq "posts"
      expect(conv_rels.first[:from_column]).to eq "user_id"
      expect(conv_rels.first[:to_table]).to eq "users"
    end

    it "does not duplicate convention relationships already covered by FK" do
      rels = inspector.relationships
      post_rels = rels.select { |r| r[:from_table] == "posts" && r[:from_column] == "user_id" }

      # Should only have the FK one, not a duplicate convention one
      expect(post_rels.length).to eq 1
      expect(post_rels.first[:type]).to eq :foreign_key
    end

    it "skips convention relationships when referenced table doesn't exist" do
      allow(connection).to receive(:tables).and_return([ "posts" ])
      allow(connection).to receive(:foreign_keys).with("posts").and_return([])
      allow(connection).to receive(:columns).with("posts").and_return([ column_id, column_user_id ])

      rels = inspector.relationships
      expect(rels).to be_empty
    end
  end

  describe "#relationships - foreign_keys not supported" do
    before do
      allow(connection).to receive(:tables).and_return([ "users", "posts" ])
      allow(connection).to receive(:respond_to?).with(:foreign_keys).and_return(false)
      allow(connection).to receive(:columns).with("users").and_return([ column_id ])
      allow(connection).to receive(:columns).with("posts").and_return([ column_id, column_user_id ])
    end

    it "falls back to convention-only relationships" do
      rels = inspector.relationships
      expect(rels.length).to eq 1
      expect(rels.first[:type]).to eq :convention
    end
  end

  describe "associations introspection" do
    before do
      allow(connection).to receive(:tables).and_return([ "users" ])
      allow(connection).to receive(:columns).with("users").and_return([ column_id ])
      allow(connection).to receive(:indexes).with("users").and_return([])
      allow(connection).to receive(:respond_to?).with(:foreign_keys).and_return(false)
      allow(connection).to receive(:primary_key).with("users").and_return("id")
      allow(connection).to receive(:quote_table_name).and_return("\"users\"")
      allow(connection).to receive(:select_value).and_return(5)
    end

    context "when a model is found" do
      let(:model_class) do
        klass = Class.new(ActiveRecord::Base)
        allow(klass).to receive(:table_name).and_return("users")
        allow(klass).to receive(:abstract_class?).and_return(false)

        assoc = double("assoc",
          name: :posts,
          macro: :has_many,
          klass: double(table_name: "posts"),
          foreign_key: "user_id",
          options: {}
        )
        allow(klass).to receive(:reflect_on_all_associations).and_return([ assoc ])
        klass
      end

      it "populates associations from reflections" do
        allow(ActiveRecord::Base).to receive(:descendants).and_return([ model_class ])
        stub_const("Rails", double(
          application: double(
            config: double(paths: { "app/models" => [] }),
            eager_load!: nil
          )
        ))

        schema = inspector.introspect
        assocs = schema["users"][:associations]

        expect(assocs.length).to eq 1
        expect(assocs.first[:name]).to eq "posts"
        expect(assocs.first[:macro]).to eq "has_many"
        expect(assocs.first[:target_table]).to eq "posts"
        expect(assocs.first[:foreign_key]).to eq "user_id"
      end
    end

    context "when no model is found" do
      it "returns empty associations" do
        allow(ActiveRecord::Base).to receive(:descendants).and_return([])
        stub_const("Rails", double(
          application: double(
            config: double(paths: { "app/models" => [] }),
            eager_load!: nil
          )
        ))

        schema = inspector.introspect
        expect(schema["users"][:associations]).to eq []
      end
    end
  end

  describe "#connection" do
    it "exposes the connection as an attribute reader" do
      expect(inspector.connection).to be connection
    end
  end

  describe "#suggest_polymorphic_composite_indexes" do
    it "suggests composite index for polymorphic columns without existing composite index" do
      polymorphics = [
        { name: "commentable", type_column: "commentable_type", id_column: "commentable_id" }
      ]
      indexes = []

      result = inspector.send(:suggest_polymorphic_composite_indexes, "comments", indexes, polymorphics)

      expect(result.length).to eq 1
      expect(result.first[:columns]).to eq [ "commentable_type", "commentable_id" ]
      expect(result.first[:reason]).to eq :polymorphic
      expect(result.first[:sql]).to include("CREATE INDEX")
      expect(result.first[:migration]).to include("add_index")
    end

    it "skips polymorphic suggestion when composite index already exists" do
      polymorphics = [
        { name: "commentable", type_column: "commentable_type", id_column: "commentable_id" }
      ]
      indexes = [
        { name: "index_comments_on_commentable", columns: [ "commentable_type", "commentable_id" ], unique: false }
      ]

      result = inspector.send(:suggest_polymorphic_composite_indexes, "comments", indexes, polymorphics)
      expect(result).to be_empty
    end

    it "returns empty when no polymorphic columns" do
      result = inspector.send(:suggest_polymorphic_composite_indexes, "posts", [], [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_join_table_composite_indexes" do
    let(:column_post_id) do
      double("column", name: "post_id", sql_type: "integer", null: false, default: nil)
    end
    let(:column_tag_id) do
      double("column", name: "tag_id", sql_type: "integer", null: false, default: nil)
    end

    it "suggests composite index for a join table" do
      columns = [
        { name: "id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "tag_id", type: "integer" }
      ]
      indexes = []
      associations = []

      result = inspector.send(:suggest_join_table_composite_indexes, "post_tags", columns, indexes, associations)

      # Should suggest both a regular and unique composite
      regular = result.select { |s| s[:reason] == :join_table }
      unique = result.select { |s| s[:reason] == :join_table_unique }
      expect(regular.length).to eq 1
      expect(regular.first[:columns]).to eq [ "post_id", "tag_id" ]
      expect(unique.length).to eq 1
    end

    it "skips suggestion when composite index already exists" do
      columns = [
        { name: "id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "tag_id", type: "integer" }
      ]
      indexes = [
        { name: "idx_post_tags", columns: [ "post_id", "tag_id" ], unique: true }
      ]
      associations = []

      result = inspector.send(:suggest_join_table_composite_indexes, "post_tags", columns, indexes, associations)
      expect(result).to be_empty
    end

    it "returns empty for non-join tables" do
      columns = [
        { name: "id", type: "integer" },
        { name: "name", type: "varchar" },
        { name: "email", type: "varchar" },
        { name: "user_id", type: "integer" }
      ]
      indexes = []
      associations = []

      result = inspector.send(:suggest_join_table_composite_indexes, "profiles", columns, indexes, associations)
      expect(result).to be_empty
    end

    it "detects join table via through association" do
      columns = [
        { name: "id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "tag_id", type: "integer" },
        { name: "extra_data", type: "text" },
        { name: "another_col", type: "text" },
        { name: "more_stuff", type: "text" }
      ]
      indexes = []
      associations = [ { name: "tags", macro: "has_many", through: "taggings", foreign_key: "post_id", target_table: "tags" } ]

      result = inspector.send(:suggest_join_table_composite_indexes, "taggings", columns, indexes, associations)
      expect(result).not_to be_empty
    end
  end

  describe "#suggest_query_driven_indexes" do
    before do
      RailsDbInspector::QueryStore.instance.clear!
    end

    it "returns empty when no queries captured" do
      result = inspector.send(:suggest_query_driven_indexes, "posts", [])
      expect(result).to be_empty
    end

    it "suggests composite index based on query patterns" do
      # Add queries that reference multiple columns together
      3.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM posts WHERE user_id = 1 AND status = 'published' ORDER BY created_at DESC",
          name: "Post Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      indexes = []
      result = inspector.send(:suggest_query_driven_indexes, "posts", indexes)

      expect(result).not_to be_empty
      expect(result.first[:reason]).to eq :query_pattern
      expect(result.first[:columns].length).to be >= 2
    end

    it "skips suggestion when composite index already covers columns" do
      3.times do
        RailsDbInspector::QueryStore.instance.add(
          sql: "SELECT * FROM posts WHERE user_id = 1 AND status = 'active'",
          name: "Post Load",
          binds: [],
          duration_ms: 5.0,
          connection_id: 1,
          timestamp: Time.now
        )
      end

      indexes = [
        { name: "idx_posts_user_status", columns: [ "user_id", "status" ], unique: false }
      ]
      result = inspector.send(:suggest_query_driven_indexes, "posts", indexes)
      expect(result).to be_empty
    end

    it "requires at least 2 occurrences before suggesting" do
      RailsDbInspector::QueryStore.instance.add(
        sql: "SELECT * FROM posts WHERE user_id = 1 AND status = 'active'",
        name: "Post Load",
        binds: [],
        duration_ms: 5.0,
        connection_id: 1,
        timestamp: Time.now
      )

      result = inspector.send(:suggest_query_driven_indexes, "posts", [])
      expect(result).to be_empty
    end
  end

  describe "#references_table?" do
    it "returns true when table is referenced" do
      expect(inspector.send(:references_table?, "SELECT * FROM posts WHERE id = 1", "posts")).to be true
    end

    it "returns false when table is not referenced" do
      expect(inspector.send(:references_table?, "SELECT * FROM users WHERE id = 1", "posts")).to be false
    end
  end

  describe "#extract_where_columns" do
    it "extracts columns from table-qualified WHERE clause" do
      sql = "SELECT * FROM posts WHERE posts.user_id = 1 AND posts.status = 'active'"
      result = inspector.send(:extract_where_columns, sql, "posts")
      expect(result).to include("user_id")
      expect(result).to include("status")
    end

    it "extracts columns from simple WHERE clause in single-table queries" do
      sql = "SELECT * FROM posts WHERE user_id = 1 AND status = 'active'"
      result = inspector.send(:extract_where_columns, sql, "posts")
      expect(result).to include("user_id")
      expect(result).to include("status")
    end
  end

  describe "#extract_order_columns" do
    it "extracts columns from table-qualified ORDER BY" do
      sql = "SELECT * FROM posts ORDER BY posts.created_at DESC"
      result = inspector.send(:extract_order_columns, sql, "posts")
      expect(result).to include("created_at")
    end

    it "extracts columns from simple ORDER BY in single-table queries" do
      sql = "SELECT * FROM posts ORDER BY created_at DESC"
      result = inspector.send(:extract_order_columns, sql, "posts")
      expect(result).to include("created_at")
    end
  end

  describe "#looks_like_join_table?" do
    it "identifies a join table with 2 FK columns and few other columns" do
      columns = [
        { name: "id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "tag_id", type: "integer" }
      ]
      expect(inspector.send(:looks_like_join_table?, "post_tags", columns)).to be true
    end

    it "rejects a table with many non-FK columns" do
      columns = [
        { name: "id", type: "integer" },
        { name: "post_id", type: "integer" },
        { name: "tag_id", type: "integer" },
        { name: "name", type: "varchar" },
        { name: "description", type: "text" },
        { name: "priority", type: "integer" }
      ]
      expect(inspector.send(:looks_like_join_table?, "post_tags", columns)).to be false
    end

    it "rejects a table with only one FK column" do
      columns = [
        { name: "id", type: "integer" },
        { name: "user_id", type: "integer" },
        { name: "name", type: "varchar" }
      ]
      expect(inspector.send(:looks_like_join_table?, "profiles", columns)).to be false
    end
  end

  describe "#suggest_sti_index" do
    it "suggests index on type column when not indexed" do
      columns = [
        { name: "id", type: "integer" },
        { name: "type", type: "varchar(255)" },
        { name: "name", type: "varchar(255)" }
      ]
      indexes = []

      result = inspector.send(:suggest_sti_index, "vehicles", columns, indexes)
      expect(result.length).to eq 1
      expect(result.first[:reason]).to eq :sti
      expect(result.first[:columns]).to eq [ "type" ]
    end

    it "skips when type column already indexed" do
      columns = [
        { name: "id", type: "integer" },
        { name: "type", type: "varchar(255)" }
      ]
      indexes = [
        { name: "index_vehicles_on_type", columns: [ "type" ], unique: false }
      ]

      result = inspector.send(:suggest_sti_index, "vehicles", columns, indexes)
      expect(result).to be_empty
    end

    it "returns empty when no type column exists" do
      columns = [
        { name: "id", type: "integer" },
        { name: "name", type: "varchar(255)" }
      ]

      result = inspector.send(:suggest_sti_index, "users", columns, [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_uniqueness_indexes" do
    before do
      stub_const("Rails", double(
        application: double(
          config: double(paths: { "app/models" => [] }),
          eager_load!: nil
        )
      ))
    end

    it "suggests unique index for validates_uniqueness_of" do
      model = Class.new(ActiveRecord::Base)
      allow(model).to receive(:table_name).and_return("users")
      allow(model).to receive(:abstract_class?).and_return(false)

      validator = double("validator",
        attributes: [ :email ],
        options: {}
      )
      allow(validator).to receive(:is_a?).with(anything).and_return(false)
      allow(validator).to receive(:is_a?).with(ActiveRecord::Validations::UniquenessValidator).and_return(true)
      allow(model).to receive(:validators).and_return([ validator ])
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ model ])

      columns = [
        { name: "id", type: "integer" },
        { name: "email", type: "varchar(255)" }
      ]
      indexes = []

      result = inspector.send(:suggest_uniqueness_indexes, "users", columns, indexes)
      expect(result.length).to eq 1
      expect(result.first[:reason]).to eq :uniqueness
      expect(result.first[:columns]).to eq [ "email" ]
    end

    it "suggests scoped unique composite index" do
      model = Class.new(ActiveRecord::Base)
      allow(model).to receive(:table_name).and_return("slugs")
      allow(model).to receive(:abstract_class?).and_return(false)

      validator = double("validator",
        attributes: [ :slug ],
        options: { scope: :sluggable_type }
      )
      allow(validator).to receive(:is_a?).with(anything).and_return(false)
      allow(validator).to receive(:is_a?).with(ActiveRecord::Validations::UniquenessValidator).and_return(true)
      allow(model).to receive(:validators).and_return([ validator ])
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ model ])

      columns = [
        { name: "id", type: "integer" },
        { name: "slug", type: "varchar" },
        { name: "sluggable_type", type: "varchar" }
      ]
      indexes = []

      result = inspector.send(:suggest_uniqueness_indexes, "slugs", columns, indexes)
      expect(result.length).to eq 1
      expect(result.first[:columns]).to include("slug", "sluggable_type")
    end

    it "skips when unique index already exists" do
      model = Class.new(ActiveRecord::Base)
      allow(model).to receive(:table_name).and_return("users")
      allow(model).to receive(:abstract_class?).and_return(false)

      validator = double("validator",
        attributes: [ :email ],
        options: {}
      )
      allow(validator).to receive(:is_a?).with(anything).and_return(false)
      allow(validator).to receive(:is_a?).with(ActiveRecord::Validations::UniquenessValidator).and_return(true)
      allow(model).to receive(:validators).and_return([ validator ])
      allow(ActiveRecord::Base).to receive(:descendants).and_return([ model ])

      columns = [
        { name: "id", type: "integer" },
        { name: "email", type: "varchar(255)" }
      ]
      indexes = [
        { name: "index_users_on_email", columns: [ "email" ], unique: true }
      ]

      result = inspector.send(:suggest_uniqueness_indexes, "users", columns, indexes)
      expect(result).to be_empty
    end

    it "returns empty when no model found" do
      allow(ActiveRecord::Base).to receive(:descendants).and_return([])

      result = inspector.send(:suggest_uniqueness_indexes, "unknown", [], [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_covering_indexes" do
    before do
      RailsDbInspector::QueryStore.instance.clear!
    end

    it "suggests covering index for WHERE + ORDER BY pattern" do
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

      result = inspector.send(:suggest_covering_indexes, "posts", [])
      expect(result).not_to be_empty
      expect(result.first[:reason]).to eq :covering
    end

    it "returns empty when no queries exist" do
      result = inspector.send(:suggest_covering_indexes, "posts", [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_partial_indexes_for_booleans" do
    it "suggests partial index for skewed boolean column" do
      allow(connection).to receive(:quote_table_name).and_return('"users"')
      allow(connection).to receive(:quote_column_name).and_return('"active"')
      allow(connection).to receive(:select_value).and_return(200, 950, 50)

      columns = [
        { name: "id", type: "integer" },
        { name: "active", type: "boolean" }
      ]
      indexes = []

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, indexes)
      expect(result.length).to eq 1
      expect(result.first[:reason]).to eq :partial_boolean
    end

    it "skips when data is not skewed" do
      allow(connection).to receive(:quote_table_name).and_return('"users"')
      allow(connection).to receive(:quote_column_name).and_return('"active"')
      allow(connection).to receive(:select_value).and_return(1000, 500, 500)

      columns = [
        { name: "id", type: "integer" },
        { name: "active", type: "boolean" }
      ]
      indexes = []

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, indexes)
      expect(result).to be_empty
    end

    it "skips when column already indexed" do
      allow(connection).to receive(:quote_table_name).and_return('"users"')
      allow(connection).to receive(:quote_column_name).and_return('"active"')
      allow(connection).to receive(:select_value).and_return(200, 950, 50)

      columns = [
        { name: "id", type: "integer" },
        { name: "active", type: "boolean" }
      ]
      indexes = [
        { name: "index_users_on_active", columns: [ "active" ], unique: false }
      ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, indexes)
      expect(result).to be_empty
    end

    it "returns empty for tables with no boolean columns" do
      columns = [
        { name: "id", type: "integer" },
        { name: "name", type: "varchar" }
      ]

      result = inspector.send(:suggest_partial_indexes_for_booleans, "users", columns, [])
      expect(result).to be_empty
    end
  end

  describe "#detect_redundant_indexes" do
    it "detects single-column index redundant with composite" do
      indexes = [
        { name: "index_posts_on_user_id", columns: [ "user_id" ], unique: false },
        { name: "index_posts_on_user_id_and_created_at", columns: [ "user_id", "created_at" ], unique: false }
      ]

      result = inspector.send(:detect_redundant_indexes, "posts", indexes)
      expect(result.length).to eq 1
      expect(result.first[:reason]).to eq :redundant
      expect(result.first[:redundant_index]).to eq "index_posts_on_user_id"
      expect(result.first[:covered_by]).to eq "index_posts_on_user_id_and_created_at"
    end

    it "does not flag non-prefix indexes as redundant" do
      indexes = [
        { name: "index_posts_on_user_id", columns: [ "user_id" ], unique: false },
        { name: "index_posts_on_status_and_user_id", columns: [ "status", "user_id" ], unique: false }
      ]

      result = inspector.send(:detect_redundant_indexes, "posts", indexes)
      expect(result).to be_empty
    end

    it "returns empty with fewer than 2 indexes" do
      indexes = [
        { name: "index_posts_on_user_id", columns: [ "user_id" ], unique: false }
      ]

      result = inspector.send(:detect_redundant_indexes, "posts", indexes)
      expect(result).to be_empty
    end

    it "detects two-column index redundant with three-column index" do
      indexes = [
        { name: "idx_a_b", columns: [ "a", "b" ], unique: false },
        { name: "idx_a_b_c", columns: [ "a", "b", "c" ], unique: false }
      ]

      result = inspector.send(:detect_redundant_indexes, "t", indexes)
      expect(result.length).to eq 1
      expect(result.first[:redundant_index]).to eq "idx_a_b"
    end
  end

  describe "#suggest_soft_delete_partial_index" do
    it "suggests partial index for deleted_at column" do
      columns = [
        { name: "id", type: "integer" },
        { name: "name", type: "varchar" },
        { name: "deleted_at", type: "datetime" }
      ]
      indexes = []

      result = inspector.send(:suggest_soft_delete_partial_index, "posts", columns, indexes)
      expect(result.length).to eq 1
      expect(result.first[:reason]).to eq :soft_delete
      expect(result.first[:columns]).to eq [ "deleted_at" ]
      expect(result.first[:sql]).to include("WHERE deleted_at IS NULL")
    end

    it "suggests partial index for discarded_at column" do
      columns = [
        { name: "id", type: "integer" },
        { name: "discarded_at", type: "datetime" }
      ]

      result = inspector.send(:suggest_soft_delete_partial_index, "posts", columns, [])
      expect(result.length).to eq 1
      expect(result.first[:sql]).to include("WHERE discarded_at IS NULL")
    end

    it "suggests partial index for archived_at column" do
      columns = [
        { name: "id", type: "integer" },
        { name: "archived_at", type: "datetime" }
      ]

      result = inspector.send(:suggest_soft_delete_partial_index, "posts", columns, [])
      expect(result.length).to eq 1
      expect(result.first[:sql]).to include("WHERE archived_at IS NULL")
    end

    it "skips when already indexed" do
      columns = [
        { name: "id", type: "integer" },
        { name: "deleted_at", type: "datetime" }
      ]
      indexes = [
        { name: "index_posts_active", columns: [ "deleted_at" ], unique: false }
      ]

      result = inspector.send(:suggest_soft_delete_partial_index, "posts", columns, indexes)
      expect(result).to be_empty
    end

    it "returns empty when no soft-delete column" do
      columns = [
        { name: "id", type: "integer" },
        { name: "name", type: "varchar" }
      ]

      result = inspector.send(:suggest_soft_delete_partial_index, "posts", columns, [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_timestamp_ordering_indexes" do
    before do
      RailsDbInspector::QueryStore.instance.clear!
    end

    it "suggests index on created_at used in ORDER BY" do
      3.times do
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
      indexes = []

      result = inspector.send(:suggest_timestamp_ordering_indexes, "posts", columns, indexes)
      expect(result.length).to eq 1
      expect(result.first[:reason]).to eq :timestamp_order
      expect(result.first[:columns]).to eq [ "created_at" ]
    end

    it "skips when already indexed" do
      3.times do
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
      indexes = [
        { name: "index_posts_on_created_at", columns: [ "created_at" ], unique: false }
      ]

      result = inspector.send(:suggest_timestamp_ordering_indexes, "posts", columns, indexes)
      expect(result).to be_empty
    end

    it "returns empty when no queries exist" do
      columns = [
        { name: "id", type: "integer" },
        { name: "created_at", type: "datetime" }
      ]

      result = inspector.send(:suggest_timestamp_ordering_indexes, "posts", columns, [])
      expect(result).to be_empty
    end

    it "returns empty when no timestamp columns" do
      columns = [
        { name: "id", type: "integer" },
        { name: "name", type: "varchar" }
      ]

      RailsDbInspector::QueryStore.instance.add(
        sql: "SELECT * FROM posts ORDER BY posts.name",
        name: "Post Load",
        binds: [],
        duration_ms: 5.0,
        connection_id: 1,
        timestamp: Time.now
      )

      result = inspector.send(:suggest_timestamp_ordering_indexes, "posts", columns, [])
      expect(result).to be_empty
    end
  end

  describe "#suggest_counter_cache_indexes" do
    before do
      RailsDbInspector::QueryStore.instance.clear!
    end

    it "suggests index on _count column used in ORDER BY" do
      3.times do
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
      indexes = []

      result = inspector.send(:suggest_counter_cache_indexes, "users", columns, indexes)
      expect(result.length).to eq 1
      expect(result.first[:reason]).to eq :counter_cache
      expect(result.first[:columns]).to eq [ "posts_count" ]
    end

    it "skips when already indexed" do
      3.times do
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
      indexes = [
        { name: "index_users_on_posts_count", columns: [ "posts_count" ], unique: false }
      ]

      result = inspector.send(:suggest_counter_cache_indexes, "users", columns, indexes)
      expect(result).to be_empty
    end

    it "returns empty when no queries exist" do
      columns = [
        { name: "id", type: "integer" },
        { name: "posts_count", type: "integer" }
      ]

      result = inspector.send(:suggest_counter_cache_indexes, "users", columns, [])
      expect(result).to be_empty
    end

    it "returns empty when no _count columns" do
      columns = [
        { name: "id", type: "integer" },
        { name: "name", type: "varchar" }
      ]

      RailsDbInspector::QueryStore.instance.add(
        sql: "SELECT * FROM users ORDER BY users.name",
        name: "User Load",
        binds: [],
        duration_ms: 5.0,
        connection_id: 1,
        timestamp: Time.now
      )

      result = inspector.send(:suggest_counter_cache_indexes, "users", columns, [])
      expect(result).to be_empty
    end
  end

  describe "#table_sizes" do
    context "with PostgreSQL adapter" do
      before do
        allow(connection).to receive(:adapter_name).and_return("PostgreSQL")
        allow(connection).to receive(:tables).and_return(%w[users posts schema_migrations ar_internal_metadata])
        allow(connection).to receive(:quote_table_name) { |t| "\"#{t}\"" }
      end

      it "returns size info per table" do
        allow(connection).to receive(:select_value).with("SELECT pg_total_relation_size('users')").and_return(65536)
        allow(connection).to receive(:select_value).with("SELECT pg_relation_size('users')").and_return(49152)
        allow(connection).to receive(:select_value).with("SELECT pg_total_relation_size('posts')").and_return(131072)
        allow(connection).to receive(:select_value).with("SELECT pg_relation_size('posts')").and_return(98304)
        allow(connection).to receive(:select_value).with(/SELECT COUNT/).and_return(100)

        sizes = inspector.table_sizes
        expect(sizes).to include("users", "posts")
        expect(sizes).not_to include("schema_migrations", "ar_internal_metadata")
        expect(sizes["users"][:total_size]).to eq(65536)
        expect(sizes["users"][:data_size]).to eq(49152)
        expect(sizes["users"][:index_size]).to eq(16384)
        expect(sizes["users"][:row_count]).to eq(100)
      end
    end

    context "with MySQL adapter" do
      before do
        allow(connection).to receive(:adapter_name).and_return("Mysql2")
        allow(connection).to receive(:quote_table_name) { |t| "`#{t}`" }
      end

      it "returns size info from information_schema" do
        rows = [
          { "table_name" => "users", "data_length" => 32768, "index_length" => 8192 },
          { "table_name" => "posts", "data_length" => 65536, "index_length" => 16384 },
          { "table_name" => "schema_migrations", "data_length" => 1024, "index_length" => 512 }
        ]
        allow(connection).to receive(:select_all).and_return(rows)
        allow(connection).to receive(:select_value).with(/SELECT COUNT/).and_return(50)

        sizes = inspector.table_sizes
        expect(sizes).to include("users", "posts")
        expect(sizes).not_to include("schema_migrations")
        expect(sizes["users"][:total_size]).to eq(40960)
        expect(sizes["users"][:data_size]).to eq(32768)
        expect(sizes["users"][:index_size]).to eq(8192)
      end
    end

    context "with SQLite adapter" do
      before do
        allow(connection).to receive(:adapter_name).and_return("SQLite")
        allow(connection).to receive(:tables).and_return(%w[users schema_migrations])
        allow(connection).to receive(:quote_table_name) { |t| "\"#{t}\"" }
      end

      it "returns size info using dbstat" do
        allow(connection).to receive(:select_value).with("PRAGMA page_size").and_return(4096)
        allow(connection).to receive(:select_value).with(/SELECT SUM/).and_return(10)
        allow(connection).to receive(:select_value).with(/SELECT COUNT/).and_return(25)

        sizes = inspector.table_sizes
        expect(sizes).to include("users")
        expect(sizes).not_to include("schema_migrations")
        expect(sizes["users"][:total_size]).to eq(40960)
        expect(sizes["users"][:row_count]).to eq(25)
      end

      it "handles missing dbstat gracefully" do
        allow(connection).to receive(:select_value).with("PRAGMA page_size").and_return(4096)
        allow(connection).to receive(:select_value).with(/SELECT SUM/).and_raise(StandardError.new("no such table: dbstat"))
        allow(connection).to receive(:select_value).with(/SELECT COUNT/).and_return(25)

        sizes = inspector.table_sizes
        expect(sizes["users"][:total_size]).to be_nil
        expect(sizes["users"][:row_count]).to eq(25)
      end
    end

    context "with unknown adapter" do
      it "returns empty hash" do
        allow(connection).to receive(:adapter_name).and_return("Oracle")
        expect(inspector.table_sizes).to eq({})
      end
    end

    context "when an error occurs" do
      it "returns empty hash" do
        allow(connection).to receive(:adapter_name).and_raise(StandardError.new("oops"))
        expect(inspector.table_sizes).to eq({})
      end
    end
  end
end
