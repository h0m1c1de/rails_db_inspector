# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::Explain::MySql do
  let(:connection) { double("connection") }
  subject(:explainer) { described_class.new(connection) }

  describe "#explain" do
    context "without analyze" do
      it "runs EXPLAIN and returns columns and rows" do
        result = double("result",
          columns: ["id", "select_type", "table"],
          rows: [[1, "SIMPLE", "users"]]
        )

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN SELECT * FROM users")
          .and_return(result)

        output = explainer.explain("SELECT * FROM users")

        expect(output[:adapter]).to eq "mysql"
        expect(output[:analyze]).to be false
        expect(output[:columns]).to eq ["id", "select_type", "table"]
        expect(output[:rows]).to eq [[1, "SIMPLE", "users"]]
      end

      it "strips existing EXPLAIN prefix" do
        result = double("result", columns: [], rows: [])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN SELECT 1")
          .and_return(result)

        explainer.explain("EXPLAIN SELECT 1")
      end

      it "strips EXPLAIN ANALYZE prefix" do
        result = double("result", columns: [], rows: [])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN SELECT 1")
          .and_return(result)

        explainer.explain("EXPLAIN ANALYZE SELECT 1")
      end
    end

    context "with analyze" do
      it "runs EXPLAIN ANALYZE" do
        result = double("result", columns: ["EXPLAIN"], rows: [["-> Table scan"]])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN ANALYZE SELECT * FROM users")
          .and_return(result)

        output = explainer.explain("SELECT * FROM users", analyze: true)

        expect(output[:adapter]).to eq "mysql"
        expect(output[:analyze]).to be true
      end

      it "calls select_only! for safety" do
        expect(RailsDbInspector::Explain).to receive(:select_only!).with("UPDATE users SET x = 1")
          .and_raise(RailsDbInspector::Explain::DangerousQuery)

        expect { explainer.explain("UPDATE users SET x = 1", analyze: true) }
          .to raise_error(RailsDbInspector::Explain::DangerousQuery)
      end
    end
  end
end
