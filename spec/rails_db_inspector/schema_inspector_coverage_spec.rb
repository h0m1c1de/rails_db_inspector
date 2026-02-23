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
end
