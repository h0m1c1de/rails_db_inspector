# frozen_string_literal: true

module RailsDbInspector
  class Engine < ::Rails::Engine
    isolate_namespace RailsDbInspector

    initializer "rails_db_inspector.subscribe_sql" do
      next unless RailsDbInspector.configuration.enabled
      RailsDbInspector::SqlSubscriber.install!
    end
  end
end
