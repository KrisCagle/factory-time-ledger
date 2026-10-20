require "net/http"
require "json"

module Harvest
  # Minimal Harvest API v2 client. With no credentials configured it runs in
  # dry-run mode: it builds the request but never sends it.
  class Client
    API_BASE = "https://api.harvestapp.com/v2".freeze

    Response = Struct.new(:ok, :dry_run, :entry_id, :error, :payload, keyword_init: true)

    def self.configured? = ENV["HARVEST_ACCESS_TOKEN"].present? && ENV["HARVEST_ACCOUNT_ID"].present?

    def dry_run? = !self.class.configured?

    # Harvest accounts tracking time as durations accept `hours`. Accounts set
    # to start/end timestamps need started_time/ended_time instead; that is not
    # handled in v1 and Harvest will return an error explaining so.
    def create_time_entry(payload)
      return Response.new(ok: true, dry_run: true, payload:) if dry_run?

      uri = URI("#{API_BASE}/time_entries")
      request = Net::HTTP::Post.new(uri, headers)
      request.body = payload.to_json
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
      body = JSON.parse(response.body.presence || "{}")

      if response.is_a?(Net::HTTPSuccess)
        Response.new(ok: true, dry_run: false, entry_id: body["id"], payload:)
      else
        Response.new(ok: false, dry_run: false, error: "Harvest #{response.code}: #{body['message'] || response.body}", payload:)
      end
    rescue StandardError => e
      Response.new(ok: false, dry_run: false, error: "#{e.class}: #{e.message}", payload:)
    end

    private

      def headers
        {
          "Authorization" => "Bearer #{ENV.fetch('HARVEST_ACCESS_TOKEN')}",
          "Harvest-Account-Id" => ENV.fetch("HARVEST_ACCOUNT_ID"),
          "User-Agent" => "factory-time-ledger",
          "Content-Type" => "application/json"
        }
      end
  end
end
