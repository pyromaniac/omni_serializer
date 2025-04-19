# frozen_string_literal: true

require 'omni_serializer'
require 'active_record'
require 'database_cleaner/active_record'
require_relative 'support/schema'
require_relative 'support/models'
require_relative 'support/resources'
require_relative 'support/class_helpers'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  config.disable_monkey_patching!

  config.order = :random
  Kernel.srand config.seed

  config.include ClassHelpers

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
