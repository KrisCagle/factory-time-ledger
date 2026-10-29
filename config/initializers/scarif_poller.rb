# Background Scarif sync while `bin/rails server` (bin/dev) runs. Off in tests,
# the console and rake tasks. Set SCARIF_POLL=false in .env to turn it off and
# use Settings → Sync now instead.
Rails.application.config.after_initialize do
  server = defined?(Rails::Server) || $PROGRAM_NAME.include?("puma")
  if server && !Rails.env.test? && ENV["SCARIF_POLL"] != "false" && Scarif::Client.configured?
    Scarif::Poller.start
  end
end
