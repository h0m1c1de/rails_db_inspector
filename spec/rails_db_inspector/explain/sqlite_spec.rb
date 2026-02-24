# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::Explain::Sqlite do
  let(:connection) { double("connection") }
  subject(:explainer) { described_class.new(connection) }

  describe "#explain" do
    context "without analyze" do
      it "runs EXPLAIN QUERY PLAN and returns structured plan" do
        result = double("result",
          columns: [ "id", "parent", "notused", "detail" ],
          rows: [ [ 2, 0, 0, "SCAN users" ] ]
        )

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN QUERY PLAN SELECT * FROM users")
          .and_return(result)

        output = explainer.explain("SELECT * FROM users")

        expect(output[:adapter]).to eq "sqlite"
        expect(output[:analyze]).to be false
        expect(output[:columns]).to eq [ "id", "parent", "notused", "detail" ]
        expect(output[:rows]).to eq [ [ 2, 0, 0, "SCAN users" ] ]
        expect(output[:plan].first["detail"]).to eq "SCAN users"
      end

      it "strips existing EXPLAIN QUERY PLAN prefix" do
        result = double("result", columns: [], rows: [])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN QUERY PLAN SELECT 1")
          .and_return(result)

        explainer.explain("EXPLAIN QUERY PLAN SELECT 1")
      end

      it "strips existing EXPLAIN prefix" do
        result = double("result", columns: [], rows: [])

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN QUERY PLAN SELECT 1")
          .and_return(result)

        explainer.explain("EXPLAIN SELECT 1")
      end
    end

    context "with analyze" do
      it "calls select_only! for safety" do
        result = double("result", columns: [], rows: [])
        allow(connection).to receive(:exec_query).and_return(result)

        expect(RailsDbInspector::Explain).to receive(:select_only!).and_call_original

        explainer.explain("SELECT 1", analyze: true)
      end

      it "runs EXPLAIN QUERY PLAN with analyze flag" do
        result = double("result",
          columns: [ "id", "parent", "notused", "detail" ],
          rows: [ [ 2, 0, 0, "SEARCH users USING INDEX idx_users_email (email=?)" ] ]
        )

        expect(connection).to receive(:exec_query)
          .with("EXPLAIN QUERY PLAN SELECT * FROM users WHERE email = 'test'")
          .and_return(result)

        output = explainer.explain("SELECT * FROM users WHERE email = 'test'", analyze: true)

        expect(output[:adapter]).to eq "sqlite"
        expect(output[:analyze]).to be true
        expect(output[:plan].first["detail"]).to include("SEARCH users")
      end
    end
  end
end
