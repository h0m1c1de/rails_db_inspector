# frozen_string_literal: true

module RailsDbInspector
  class Configuration
    attr_accessor :enabled
    attr_accessor :max_queries
    attr_accessor :allow_explain_analyze
    attr_accessor :show_widget
    attr_accessor :allow_console_writes

    def initialize
      @enabled = true
      @max_queries = 2_000
      @allow_explain_analyze = false
      @show_widget = true
      @allow_console_writes = false
    end
  end
end
