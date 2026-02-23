# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector do
  describe "VERSION" do
    it "is defined" do
      expect(RailsDbInspector::VERSION).to be_a(String)
    end

    it "follows semantic versioning" do
      expect(RailsDbInspector::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe "Error" do
    it "is a StandardError subclass" do
      expect(RailsDbInspector::Error).to be < StandardError
    end
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(RailsDbInspector.configuration).to be_a(RailsDbInspector::Configuration)
    end

    it "memoizes the configuration" do
      config = RailsDbInspector.configuration
      expect(RailsDbInspector.configuration).to be(config)
    end
  end

  describe ".configure" do
    it "yields the configuration object" do
      expect { |b| RailsDbInspector.configure(&b) }
        .to yield_with_args(RailsDbInspector.configuration)
    end

    it "allows setting configuration values" do
      RailsDbInspector.configure do |c|
        c.enabled = false
        c.max_queries = 500
      end

      expect(RailsDbInspector.configuration.enabled).to be false
      expect(RailsDbInspector.configuration.max_queries).to eq 500
    end
  end
end
