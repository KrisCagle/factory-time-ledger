require "net/http"
require "json"

module Scarif
  # Read-only client for Scarif's /api/v2. It only ever sends GET requests, and
  # every endpoint it calls needs nothing more than the `work_item:read` scope.
  #
  #   SCARIF_API_TOKEN  a Scarif personal API token (Settings → API tokens)
  #   SCARIF_URL        defaults to https://scarif.twinsun.dev
  class Client
    DEFAULT_URL = "https://scarif.twinsun.dev".freeze

    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end
    end

    Page = Struct.new(:items, :next_cursor, :has_more, keyword_init: true)

    def self.configured? = ENV["SCARIF_API_TOKEN"].present?
    def self.base_url = ENV.fetch("SCARIF_URL", DEFAULT_URL).to_s.chomp("/")

    # { "user" => { "id", "email", "name" }, "token" => { "name", "scopes", ... } }
    def me = get("/api/v2/me").first

    # Newest-updated first. Pass next_cursor back to get the following page.
    def work_items(cursor: nil, limit: 100)
      query = { limit: }
      query[:cursor] = cursor if cursor
      body, headers = get("/api/v2/work_items", query)
      Page.new(items: Array(body), next_cursor: headers["x-next-cursor"], has_more: headers["x-has-more"] == "true")
    end

    # The detailed view: includes `stages`.
    def work_item(id) = get("/api/v2/work_items/#{escape(id)}").first

    # Factory node runs, each with started_at, completed_at and cost_usd.
    def node_runs(id) = Array(get("/api/v2/work_items/#{escape(id)}/node_runs").first["node_runs"])

    # Every ask (open, answered, withdrawn) on work items with this Jira key.
    def factory_asks(jira_key:) = Array(get("/api/v2/factory_asks", { state: "all", jira_key: }).first["asks"])

    private

      def escape(id) = ERB::Util.url_encode(id.to_s)

      # Returns [parsed_body, lowercase_headers].
      def get(path, query = {})
        raise Error, "Scarif isn't connected. Add SCARIF_API_TOKEN to .env and restart." unless self.class.configured?

        uri = URI("#{self.class.base_url}#{path}")
        uri.query = URI.encode_www_form(query) if query.any?
        request = Net::HTTP::Get.new(uri, headers)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
          http.request(request)
        end
        body = response.body.present? ? JSON.parse(response.body) : {}
        return [body, response.each_header.to_h] if response.is_a?(Net::HTTPSuccess)

        raise Error.new(error_message(response, body), status: response.code.to_i)
      rescue JSON::ParserError
        raise Error.new("Scarif #{response&.code}: unexpected response (is SCARIF_URL right?)", status: response&.code.to_i)
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        raise Error, "Couldn't reach Scarif at #{self.class.base_url} (#{e.class.name.demodulize})"
      end

      def error_message(response, body)
        detail = body.is_a?(Hash) ? (body["error"] || body["message"]) : nil
        case response.code.to_i
        when 401 then "Scarif rejected the token (401). Check SCARIF_API_TOKEN, or create a new one."
        when 403 then "Scarif says the token can't read this (403). It needs the work_item:read scope.#{" #{detail}" if detail}"
        else "Scarif #{response.code}: #{detail || response.message}"
        end
      end

      def headers
        {
          "Authorization" => "Bearer #{ENV.fetch('SCARIF_API_TOKEN')}",
          "Accept" => "application/json",
          "User-Agent" => "factory-time-ledger (https://github.com/KrisCagle/factory-time-ledger)"
        }
      end
  end
end
