# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::Engine do
  it "is a Rails::Engine subclass" do
    expect(described_class).to be < ::Rails::Engine
  end

  it "isolates the namespace" do
    expect(described_class.isolated?).to be true
  end
end
