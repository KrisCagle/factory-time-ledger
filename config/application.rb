require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module FactoryTimeLedger
  class Application < Rails::Application
    config.load_defaults 8.0

    # lib/attribution is plain Ruby (no Rails) so it can be tested on its own.
    config.autoload_lib(ignore: %w[tasks attribution])

    config.time_zone = ENV.fetch("LEDGER_TIME_ZONE", "Central Time (US & Canada)")
    config.generators.system_tests = nil
  end
end
