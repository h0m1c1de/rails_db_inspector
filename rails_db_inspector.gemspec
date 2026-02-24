require_relative "lib/rails_db_inspector/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_db_inspector"
  spec.version     = RailsDbInspector::VERSION
  spec.authors     = [ "samuel-murphy" ]
  spec.email       = [ "samuelmurphy15@gmail.com" ]
  spec.homepage    = "https://github.com/h0m1c1de/rails_db_inspector"
  spec.summary     = "Mountable Rails engine for SQL query monitoring, N+1 detection, EXPLAIN analysis, smart index suggestions, and schema visualization."
  spec.description = "Rails DB Inspector is a mountable Rails engine that captures SQL queries in real time, detects N+1 query patterns, runs EXPLAIN/EXPLAIN ANALYZE plans, suggests missing and redundant indexes, and visualizes your database schema — all from a built-in dashboard. Supports PostgreSQL, MySQL, and SQLite."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/h0m1c1de/rails_db_inspector"
  spec.metadata["changelog_uri"] = "https://github.com/h0m1c1de/rails_db_inspector/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.1"
end
