ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end

# A procedure must hang off a level-2 process; this builds one with its
# level-1 parent so a test can say what it means in one line.
def level_two_process(company, name: "Host process")
  parent = company.pp_processes.create!(name_en: "L1 #{name}", level: 1, category: "core")
  company.pp_processes.create!(name_en: name, level: 2, parent: parent)
end
