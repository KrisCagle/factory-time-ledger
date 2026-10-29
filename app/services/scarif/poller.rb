module Scarif
  # Syncs Scarif in the background while the app server runs, every
  # SCARIF_SYNC_MINUTES (default 5). Started by config/initializers/scarif_poller.rb
  # only when a Scarif token is set and the process is `bin/rails server`.
  class Poller
    def self.interval = ENV.fetch("SCARIF_SYNC_MINUTES", "5").to_f.clamp(1, 120) * 60

    def self.start
      return if @thread&.alive?

      @thread = Thread.new do
        Thread.current.name = "scarif-poller"
        sleep 5 # let the server finish booting
        loop do
          begin
            Rails.application.executor.wrap { Scarif::Sync.call }
          rescue StandardError => e
            Rails.logger.error("[scarif-poller] #{e.class}: #{e.message}")
          end
          sleep interval
        end
      end
    end

    def self.running? = @thread&.alive? || false
  end
end
