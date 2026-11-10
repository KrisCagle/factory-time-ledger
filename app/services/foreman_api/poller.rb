module ForemanApi
  # Refreshes Foreman data in the background while the app server runs, every
  # FOREMAN_SYNC_MINUTES (default 60; Foreman saves inferred runs hourly).
  # Does nothing while signed out. Started by config/initializers/foreman_poller.rb.
  class Poller
    MUTEX = Mutex.new

    def self.interval = ENV.fetch("FOREMAN_SYNC_MINUTES", "60").to_f.clamp(5, 24 * 60) * 60

    def self.sync_once
      return nil unless MUTEX.try_lock

      begin
        @syncing = true
        Rails.application.executor.wrap { ForemanApi.signed_in? ? ForemanApi::Sync.call : nil }
      ensure
        @syncing = false
        MUTEX.unlock
      end
    end

    def self.syncing? = @syncing || false

    def self.sync_in_background
      return false if syncing?

      Thread.new do
        sync_once
      rescue StandardError => e
        Rails.logger.error("[foreman-sync] #{e.class}: #{e.message}")
      end
      true
    end

    def self.start
      return if @thread&.alive?

      @thread = Thread.new do
        Thread.current.name = "foreman-poller"
        sleep 10
        loop do
          begin
            sync_once
          rescue StandardError => e
            Rails.logger.error("[foreman-poller] #{e.class}: #{e.message}")
          end
          sleep interval
        end
      end
    end

    def self.running? = @thread&.alive? || false
  end
end
