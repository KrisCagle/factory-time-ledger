module Scarif
  # Confirms the token works, records whose it is and what it may do.
  class CheckConnection
    WRITE_SCOPES = %w[work_item:write ask:answer repo:write index:write upload:write session:manage].freeze

    Outcome = Struct.new(:ok, :message, keyword_init: true)

    def self.call(client: Client.new, setting: LedgerSetting.current) = new(client, setting).call

    def initialize(client, setting)
      @client = client
      @setting = setting
    end

    def call
      body = @client.me
      user = body["user"]
      unless user
        message = "That token belongs to a Scarif service account, not a person. Use a personal API token."
        @setting.update!(scarif_checked_at: Time.current, scarif_check_error: message)
        return Outcome.new(ok: false, message:)
      end

      scopes = Array(body.dig("token", "scopes"))
      @setting.update!(
        scarif_user_id: user["id"].to_s,
        scarif_user_name: user["name"],
        scarif_user_email: user["email"],
        scarif_token_scopes: scopes,
        scarif_checked_at: Time.current,
        scarif_check_error: nil
      )

      unless scopes.include?("work_item:read")
        message = "Connected as #{user['name']}, but the token is missing the work_item:read scope, so nothing can be read. Create a token with work_item:read."
        @setting.update!(scarif_check_error: message)
        return Outcome.new(ok: false, message:)
      end

      message = "Connected to Scarif as #{user['name']}."
      extra = scopes & WRITE_SCOPES
      message += " The token can also change things in Scarif (#{extra.join(', ')}); the ledger only reads, but a token with just work_item:read is safer." if extra.any?
      Outcome.new(ok: true, message:)
    rescue Client::Error => e
      @setting.update!(scarif_checked_at: Time.current, scarif_check_error: e.message)
      Outcome.new(ok: false, message: e.message)
    end
  end
end
