# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::Explain::Postgres do
  let(:connection) { double("connection") }
  subject(:explainer) { described_class.new(connection) }

  describe "#explain" do
    context "without analyze" do
      it "runs EXPLAIN (FORMAT JSON) and returns parsed plan" do
        plan_json = [{ "Plan" => { "Node Type" => "Seq Scan" } }].to_json
        result = double("result", rows: [[plan_json]])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN (FORMAT JSON) SELECT * FROM users")
          .and_return(result)

        output = explainer.explain("SELECT * FROM users")

        expect(output[:adapter]).to eq "postgres"
        expect(output[:analyze]).to be false
        expect(output[:plan]).to be_a(Array)
        expect(output[:plan].first["Plan"]["Node Type"]).to eq "Seq Scan"
      end

      it "strips existing EXPLAIN prefix to prevent doubling" do
        plan_json = [{}].to_json
        result = double("result", rows: [[plan_json]])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN (FORMAT JSON) SELECT 1")
          .and_return(result)

        explainer.explain("EXPLAIN SELECT 1")
      end

      it "strips EXPLAIN with options prefix" do
        plan_json = [{}].to_json
        result = double("result", rows: [[plan_json]])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN (FORMAT JSON) SELECT 1")
          .and_return(result)

        explainer.explain("EXPLAIN (ANALYZE) SELECT 1")
      end
    end

    context "with analyze" do
      it "runs EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON)" do
        plan_json = [{ "Plan" => {}, "Execution Time" => 0.5 }].to_json
        result = double("result", rows: [[plan_json]])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON) SELECT * FROM users")
          .and_return(result)

        output = explainer.explain("SELECT * FROM users", analyze: true)

        expect(output[:adapter]).to eq "postgres"
        expect(output[:analyze]).to be true
      end

      it "calls select_only! to guard against non-SELECT" do
        expect(RailsDbInspector::Explain).to receive(:select_only!).with("DELETE FROM users")
          .and_raise(RailsDbInspector::Explain::DangerousQuery)

        expect { explainer.explain("DELETE FROM users", analyze: true) }
          .to raise_error(RailsDbInspector::Explain::DangerousQuery)
      end
    end

    it "handles already-parsed plan data (not a string)" do
      plan_data = [{ "Plan" => { "Node Type" => "Seq Scan" } }]
      result = double("result", rows: [[plan_data]])

      allow(connection).to receive(:exec_query).and_return(result)

      output = explainer.explain("SELECT 1")
      expect(output[:plan]).to eq plan_data
    end
  end
end
