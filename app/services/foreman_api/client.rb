require "net/http"
require "json"

module ForemanApi
  # Read-only HTTP client for Foreman; see ForemanApi (app/services/foreman_api.rb).
  class Client
    API = "/api/administration/v1".freeze

    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end

      def not_found? = status == 404
      def forbidden? = status == 403
    end

    def initialize(token: LedgerSetting.current.foreman_token)
      @token = token
    end

    # --- Sign-in (the CLI flow: docs/cli-login.md in twinsunllc/foreman) -------

    def self.new_verifier = SecureRandom.urlsafe_base64(48)
    def self.challenge_for(verifier) = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    def self.authorize_url(challenge:, state:, port:)
      query = { tool: TOOL_NAME, name: "Factory Time Ledger", challenge:, port:, state: }
      "#{ForemanApi.base_url}/cli-auth/authorize?#{URI.encode_www_form(query)}"
    end

    # Trades the one-time code for a token:
    # { "id", "token", "expiresAt", "email", "name", "surface", "scopes" }
    def exchange(code:, verifier:)
      request(Net::HTTP::Post, "/cli-auth/exchange", body: { code:, verifier: }, auth: false)
    end

    # --- Reads ---------------------------------------------------------------------

    # { "email", "administrator", "scopes", "surface" }
    def me = request(Net::HTTP::Get, "#{API}/me")

    # What Foreman infers about one Jira story from Jira, Harvest, and the rest.
    # Raises Error (not_found?) when Foreman doesn't follow that story.
    def inferred_run(jira_key) = request(Net::HTTP::Get, "#{API}/inferred-runs/jira:#{ERB::Util.url_encode(jira_key)}")

    # The engine's timeline across every run of a story. Needs a granted scope;
    # 404 when the engine has never run the story.
    def story_timeline(jira_key) = request(Net::HTTP::Get, "#{API}/stories/#{ERB::Util.url_encode(jira_key)}/timeline")

    private

      def request(verb, path, body: nil, auth: true)
        raise Error.new("Not signed in to Foreman. Sign in from Settings.", status: 401) if auth && @token.blank?

        uri = URI("#{ForemanApi.base_url}#{path}")
        req = verb.new(uri, headers(auth))
        req.body = body.to_json if body
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
          http.request(req)
        end
        parsed = response.body.present? ? JSON.parse(response.body) : {}
        return parsed if response.is_a?(Net::HTTPSuccess)

        raise Error.new(error_message(response, parsed), status: response.code.to_i)
      rescue JSON::ParserError
        raise Error.new("Foreman #{response&.code}: unexpected response (is FOREMAN_URL right?)", status: response&.code.to_i)
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        raise Error, "Couldn't reach Foreman at #{ForemanApi.base_url} (#{e.class.name.demodulize})"
      end

      def error_message(response, body)
        detail = body.is_a?(Hash) ? (body["detail"] || body["error"] || body["title"]) : nil
        case response.code.to_i
        when 401 then "Foreman didn't accept the sign-in (401). It may have expired; sign in again from Settings."
        when 403 then "Foreman says your account can't read this (403)#{": #{detail}" if detail}. Ask a Foreman administrator for a roster entry or a granted scope."
        when 429 then "Foreman asked us to slow down (429). Try again in a minute."
        else "Foreman #{response.code}: #{detail || response.message}"
        end
      end

      def headers(auth)
        h = { "Accept" => "application/json", "Content-Type" => "application/json",
              "User-Agent" => "factory-time-ledger (https://github.com/KrisCagle/factory-time-ledger)" }
        h["Authorization"] = "Bearer #{@token}" if auth
        h
      end
  end
end
