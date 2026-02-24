# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::Engine do
  it "is a Rails::Engine subclass" do
    expect(described_class).to be < ::Rails::Engine
  end

  it "isolates the namespace" do
    expect(described_class.isolated?).to be true
  end

  describe "initializer: rails_db_inspector.subscribe_sql" do
    let(:initializer) do
      described_class.initializers.find { |i| i.name == "rails_db_inspector.subscribe_sql" }
    end

    it "skips installation when disabled" do
      allow(RailsDbInspector.configuration).to receive(:enabled).and_return(false)
      expect(RailsDbInspector::SqlSubscriber).not_to receive(:install!)
      initializer.run(double("app"))
    end

    it "installs subscriber when enabled" do
      allow(RailsDbInspector.configuration).to receive(:enabled).and_return(true)
      allow(RailsDbInspector::SqlSubscriber).to receive(:install!)
      initializer.run(double("app"))
      expect(RailsDbInspector::SqlSubscriber).to have_received(:install!)
    end
  end

  describe "initializer: rails_db_inspector.dev_widget" do
    let(:initializer) do
      described_class.initializers.find { |i| i.name == "rails_db_inspector.dev_widget" }
    end

    let(:app) { double("app", middleware: double("middleware_stack")) }

    it "skips widget when disabled" do
      allow(RailsDbInspector.configuration).to receive(:enabled).and_return(false)
      expect(app.middleware).not_to receive(:use)
      initializer.run(app)
    end

    it "skips widget when show_widget is false" do
      allow(RailsDbInspector.configuration).to receive(:enabled).and_return(true)
      allow(RailsDbInspector.configuration).to receive(:show_widget).and_return(false)
      expect(app.middleware).not_to receive(:use)
      initializer.run(app)
    end

    it "skips widget when not in development environment" do
      allow(RailsDbInspector.configuration).to receive(:enabled).and_return(true)
      allow(RailsDbInspector.configuration).to receive(:show_widget).and_return(true)
      allow(Rails).to receive(:env).and_return(double(development?: false))
      expect(app.middleware).not_to receive(:use)
      initializer.run(app)
    end

    it "installs widget middleware when all conditions met" do
      allow(RailsDbInspector.configuration).to receive(:enabled).and_return(true)
      allow(RailsDbInspector.configuration).to receive(:show_widget).and_return(true)
      allow(Rails).to receive(:env).and_return(double(development?: true))
      allow(app.middleware).to receive(:use)
      initializer.run(app)
      expect(app.middleware).to have_received(:use).with(RailsDbInspector::DevWidgetMiddleware)
    end
  end
end
