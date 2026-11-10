# Background Foreman refresh while `bin/rails server` (bin/dev) runs. Off in
# tests, the console, and rake tasks; FOREMAN_POLL=false turns it off. It only
# calls Foreman while you're signed in (Settings → Foreman connection).
Rails.application.config.after_initialize do
  server = defined?(Rails::Server) || $PROGRAM_NAME.include?("puma")
  ForemanApi::Poller.start if server && !Rails.env.test? && ENV["FOREMAN_POLL"] != "false"
end
