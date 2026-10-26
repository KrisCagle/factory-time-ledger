require "net/http"
require "json"

module Harvest
  # Minimal Harvest API v2 client. With no credentials configured it is in
  # dry-run mode: reads are unavailable and writes build the request but never
  # send it.
  class Client
    API_BASE = "https://api.harvestapp.com/v2".freeze

    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end

      def not_found? = status == 404
    end

    Response = Struct.new(:ok, :dry_run, :entry_id, :error, :payload, keyword_init: true)

    def self.configured? = ENV["HARVEST_ACCESS_TOKEN"].present? && ENV["HARVEST_ACCOUNT_ID"].present?

    def dry_run? = !self.class.configured?

    # --- Reads ---------------------------------------------------------------

    # Account-level settings. `wants_timestamp_timers` is true when the account
    # tracks start/end times rather than durations.
    def company = get("/company")

    # The person the token belongs to.
    def me = get("/users/me")

    # Every project the token's owner is assigned to, with the tasks assigned to
    # each project. Works for regular (non-admin) Harvest users.
    def project_assignments
      results = []
      page = 1
      loop do
        body = get("/users/me/project_assignments?per_page=100&page=#{page}")
        results.concat(body.fetch("project_assignments", []))
        break if body["next_page"].blank?

        page = body["next_page"]
      end
      results
    end

    def time_entry(id) = get("/time_entries/#{Integer(id)}")

    # --- Writes --------------------------------------------------------------

    # Raises Client::Error (not_found? is true when it's already gone).
    def delete_time_entry(id)
      raise Error, "Harvest isn't connected." if dry_run?

      request(Net::HTTP::Delete, "/time_entries/#{Integer(id)}")
      true
    end

    # Harvest accounts tracking time as durations accept `hours`. Accounts set
    # to start/end timestamps need started_time/ended_time instead; SendDraft
    # refuses to send in that mode (see Settings → Test connection).
    def create_time_entry(payload)
      return Response.new(ok: true, dry_run: true, payload:) if dry_run?

      body = request(Net::HTTP::Post, "/time_entries", payload)
      Response.new(ok: true, dry_run: false, entry_id: body["id"], payload:)
    rescue Error, StandardError => e
      Response.new(ok: false, dry_run: false, error: e.message, payload:)
    end

    private

      def get(path)
        raise Error, "Harvest isn't connected. Add HARVEST_ACCESS_TOKEN and HARVEST_ACCOUNT_ID to .env and restart." if dry_run?

        request(Net::HTTP::Get, path)
      end

      def request(verb, path, payload = nil)
        uri = URI("#{API_BASE}#{path}")
        req = verb.new(uri, headers)
        req.body = payload.to_json if payload
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(req) }
        body = response.body.present? ? JSON.parse(response.body) : {}
        return body if response.is_a?(Net::HTTPSuccess)

        message = body["message"] || body["error_description"] || body["error"] || response.message
        raise Error.new("Harvest #{response.code}: #{message}", status: response.code.to_i)
      rescue JSON::ParserError
        raise Error.new("Harvest #{response&.code}: unexpected response", status: response&.code.to_i)
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
        raise Error, "Couldn't reach Harvest (#{e.class.name.demodulize})"
      end

      def headers
        {
          "Authorization" => "Bearer #{ENV.fetch('HARVEST_ACCESS_TOKEN')}",
          "Harvest-Account-Id" => ENV.fetch("HARVEST_ACCOUNT_ID"),
          "User-Agent" => "factory-time-ledger (https://github.com/KrisCagle/factory-time-ledger)",
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }
      end
  end
end
