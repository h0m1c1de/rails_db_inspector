# frozen_string_literal: true

module RailsDbInspector
  class Configuration
    attr_accessor :enabled
    attr_accessor :max_queries
    attr_accessor :allow_explain_analyze

    def initialize
      @enabled = true
      @max_queries = 2_000
      @allow_explain_analyze = false
    end
  end
end
