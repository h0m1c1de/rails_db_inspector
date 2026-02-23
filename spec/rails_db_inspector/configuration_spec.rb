# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "enables by default" do
      expect(config.enabled).to be true
    end

    it "sets max_queries to 2000" do
      expect(config.max_queries).to eq 2_000
    end

    it "disables explain analyze by default" do
      expect(config.allow_explain_analyze).to be false
    end

    it "shows widget by default" do
      expect(config.show_widget).to be true
    end
  end

  describe "accessors" do
    it "allows setting enabled" do
      config.enabled = false
      expect(config.enabled).to be false
    end

    it "allows setting max_queries" do
      config.max_queries = 100
      expect(config.max_queries).to eq 100
    end

    it "allows setting allow_explain_analyze" do
      config.allow_explain_analyze = true
      expect(config.allow_explain_analyze).to be true
    end

    it "allows setting show_widget" do
      config.show_widget = false
      expect(config.show_widget).to be false
    end
  end
end
