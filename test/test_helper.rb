ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

module ActiveSupport
  class TestCase
    parallelize(workers: 1)

    def event_payload(overrides = {})
      {
        "source" => "ai-dev-factory", "event_id" => SecureRandom.uuid, "event_type" => "pipeline_started",
        "occurred_at" => Time.current.iso8601, "jira_key" => "TEST-1", "summary" => "A ticket",
        "repo" => "acme/app", "batch_id" => "b1", "agent_points" => 2, "person_email" => "dev@example.com"
      }.merge(overrides)
    end
  end
end
