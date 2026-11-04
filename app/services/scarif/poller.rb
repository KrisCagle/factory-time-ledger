module Scarif
  # Syncs Scarif in the background while the app server runs, every
  # SCARIF_SYNC_MINUTES (default 5). Started by config/initializers/scarif_poller.rb
  # only when a Scarif token is set and the process is `bin/rails server`.
  class Poller
    def self.interval = ENV.fetch("SCARIF_SYNC_MINUTES", "5").to_f.clamp(1, 120) * 60

    MUTEX = Mutex.new

    # Runs one sync unless one is already running. Returns the outcome, or nil if skipped.
    def self.sync_once
      return nil unless MUTEX.try_lock

      begin
        @syncing = true
        Rails.application.executor.wrap { Scarif::Sync.call }
      ensure
        @syncing = false
        MUTEX.unlock
      end
    end

    def self.syncing? = @syncing || false

    # "Sync now": runs in the background so the page doesn't wait on a long first sync.
    def self.sync_in_background
      return false if syncing?

      Thread.new do
        sync_once
      rescue StandardError => e
        Rails.logger.error("[scarif-sync] #{e.class}: #{e.message}")
      end
      true
    end

    def self.start
      return if @thread&.alive?

      @thread = Thread.new do
        Thread.current.name = "scarif-poller"
        sleep 5 # let the server finish booting
        loop do
          begin
            sync_once
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
