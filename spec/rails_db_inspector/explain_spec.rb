# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::Explain do
  describe ".for_connection" do
    it "returns Postgres explainer for postgresql adapter" do
      connection = double("connection", adapter_name: "PostgreSQL")
      explainer = described_class.for_connection(connection)

      expect(explainer).to be_a(RailsDbInspector::Explain::Postgres)
    end

    it "returns MySql explainer for mysql adapter" do
      connection = double("connection", adapter_name: "Mysql2")
      explainer = described_class.for_connection(connection)

      expect(explainer).to be_a(RailsDbInspector::Explain::MySql)
    end

    it "returns Sqlite explainer for sqlite adapter" do
      connection = double("connection", adapter_name: "SQLite")
      explainer = described_class.for_connection(connection)

      expect(explainer).to be_a(RailsDbInspector::Explain::Sqlite)
    end

    it "raises UnsupportedAdapter for unknown adapters" do
      connection = double("connection", adapter_name: "Oracle")

      expect { described_class.for_connection(connection) }
        .to raise_error(RailsDbInspector::Explain::UnsupportedAdapter, /Oracle/)
    end
  end

  describe ".select_only!" do
    it "does not raise for SELECT statements" do
      expect { described_class.select_only!("SELECT * FROM users") }.not_to raise_error
    end

    it "does not raise for SELECT with leading whitespace" do
      expect { described_class.select_only!("  SELECT 1") }.not_to raise_error
    end

    it "raises DangerousQuery for DELETE statements" do
      expect { described_class.select_only!("DELETE FROM users") }
        .to raise_error(RailsDbInspector::Explain::DangerousQuery)
    end

    it "raises DangerousQuery for UPDATE statements" do
      expect { described_class.select_only!("UPDATE users SET name = 'x'") }
        .to raise_error(RailsDbInspector::Explain::DangerousQuery)
    end

    it "raises DangerousQuery for INSERT statements" do
      expect { described_class.select_only!("INSERT INTO users VALUES (1)") }
        .to raise_error(RailsDbInspector::Explain::DangerousQuery)
    end
  end

  describe "UnsupportedAdapter" do
    it "is a StandardError subclass" do
      expect(RailsDbInspector::Explain::UnsupportedAdapter).to be < StandardError
    end
  end

  describe "DangerousQuery" do
    it "is a StandardError subclass" do
      expect(RailsDbInspector::Explain::DangerousQuery).to be < StandardError
    end
  end
end
