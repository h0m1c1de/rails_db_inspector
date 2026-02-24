# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::SqlSubscriber do
  describe "IGNORED_NAMES" do
    it "includes SCHEMA" do
      expect(described_class::IGNORED_NAMES).to include("SCHEMA")
    end

    it "includes TRANSACTION" do
      expect(described_class::IGNORED_NAMES).to include("TRANSACTION")
    end

    it "includes schema migration loads" do
      expect(described_class::IGNORED_NAMES).to include("ActiveRecord::SchemaMigration Load")
    end

    it "includes internal metadata loads" do
      expect(described_class::IGNORED_NAMES).to include("ActiveRecord::InternalMetadata Load")
    end
  end

  describe ".install!" do
    it "subscribes to sql.active_record notifications" do
      described_class.instance_variable_set(:@installed, false)
      expect(ActiveSupport::Notifications).to receive(:subscribe).with("sql.active_record")
      described_class.install!
    end

    it "only installs once" do
      described_class.instance_variable_set(:@installed, false)
      allow(ActiveSupport::Notifications).to receive(:subscribe)
      described_class.install!
      described_class.install!

      expect(ActiveSupport::Notifications).to have_received(:subscribe).once
    end

    context "when processing events" do
      let(:store) { RailsDbInspector::QueryStore.instance }

      # Install exactly once for all examples in this context.
      # Do NOT reset @installed — that stacks duplicate subscribers.
      before(:context) do
        RailsDbInspector::SqlSubscriber.instance_variable_set(:@installed, false)
        RailsDbInspector::SqlSubscriber.install!
      end

      before { store.clear! }
      after  { store.clear! }

      it "records regular SQL queries" do
        ActiveSupport::Notifications.instrument("sql.active_record",
          name: "User Load",
          sql: "SELECT * FROM users",
          binds: [],
          connection_id: 1,
          cached: false
        )

        queries = store.all
        expect(queries.length).to eq 1
        expect(queries.first.sql).to eq "SELECT * FROM users"
        expect(queries.first.name).to eq "User Load"
      end

      it "ignores SCHEMA queries" do
        ActiveSupport::Notifications.instrument("sql.active_record",
          name: "SCHEMA",
          sql: "SHOW TABLES",
          binds: [],
          connection_id: 1,
          cached: false
        )

        expect(store.all).to be_empty
      end

      it "ignores TRANSACTION queries" do
        ActiveSupport::Notifications.instrument("sql.active_record",
          name: "TRANSACTION",
          sql: "BEGIN",
          binds: [],
          connection_id: 1,
          cached: false
        )

        expect(store.all).to be_empty
      end

      it "ignores BEGIN/COMMIT/ROLLBACK regardless of name" do
        %w[BEGIN COMMIT ROLLBACK].each do |stmt|
          ActiveSupport::Notifications.instrument("sql.active_record",
            name: "Some Name",
            sql: stmt,
            binds: [],
            connection_id: 1,
            cached: false
          )
        end

        expect(store.all).to be_empty
      end

      it "ignores EXPLAIN queries" do
        ActiveSupport::Notifications.instrument("sql.active_record",
          name: "EXPLAIN",
          sql: "EXPLAIN SELECT * FROM users",
          binds: [],
          connection_id: 1,
          cached: false
        )

        expect(store.all).to be_empty
      end

      it "ignores cached queries" do
        ActiveSupport::Notifications.instrument("sql.active_record",
          name: "User Load",
          sql: "SELECT * FROM users",
          binds: [],
          connection_id: 1,
          cached: true
        )

        expect(store.all).to be_empty
      end

      it "ignores empty SQL" do
        ActiveSupport::Notifications.instrument("sql.active_record",
          name: "User Load",
          sql: "   ",
          binds: [],
          connection_id: 1,
          cached: false
        )

        expect(store.all).to be_empty
      end

      it "records timestamp as Time when event.time is already a Time" do
        ActiveSupport::Notifications.instrument("sql.active_record",
          name: "User Load",
          sql: "SELECT 1",
          binds: [],
          connection_id: 1,
          cached: false
        )

        expect(store.all.length).to eq 1
        expect(store.all.first.timestamp).to be_a(Time)
      end
    end
  end
end
