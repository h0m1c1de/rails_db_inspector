# frozen_string_literal: true

require_relative "rails_db_inspector/version"
require_relative "rails_db_inspector/engine"
require_relative "rails_db_inspector/configuration"
require_relative "rails_db_inspector/query_store"
require_relative "rails_db_inspector/sql_subscriber"
require_relative "rails_db_inspector/explain"
require_relative "rails_db_inspector/explain/postgres"
require_relative "rails_db_inspector/explain/my_sql"
require_relative "rails_db_inspector/explain/sqlite"
require_relative "rails_db_inspector/schema_inspector"

module RailsDbInspector
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
