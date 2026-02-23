# frozen_string_literal: true

require_relative "dev_widget_middleware"

module RailsDbInspector
  class Engine < ::Rails::Engine
    isolate_namespace RailsDbInspector

    initializer "rails_db_inspector.subscribe_sql" do
      next unless RailsDbInspector.configuration.enabled
      RailsDbInspector::SqlSubscriber.install!
    end

    initializer "rails_db_inspector.dev_widget" do |app|
      next unless RailsDbInspector.configuration.enabled
      next unless RailsDbInspector.configuration.show_widget
      next unless Rails.env.development?

      app.middleware.use RailsDbInspector::DevWidgetMiddleware
    end
  end
end
