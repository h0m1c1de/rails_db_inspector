# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/bin/"
  enable_coverage :branch
  minimum_coverage line: 95, branch: 85
end

require "bundler/setup"

# Load Rails components in the correct order
require "active_support"
require "active_support/notifications"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/string/output_safety"
require "active_model"
require "active_model/type"
require "active_record"
require "action_controller"
require "rails"

require "rails_db_inspector"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Reset configuration between tests
  config.before(:each) do
    RailsDbInspector.instance_variable_set(:@configuration, nil)
  end
end
