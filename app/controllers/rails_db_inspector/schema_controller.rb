# frozen_string_literal: true

module RailsDbInspector
  class SchemaController < ApplicationController
    include RailsDbInspector::ApplicationHelper

    def index
      inspector = RailsDbInspector::SchemaInspector.new
      @schema = inspector.introspect
      @relationships = inspector.relationships
    end
  end
end
