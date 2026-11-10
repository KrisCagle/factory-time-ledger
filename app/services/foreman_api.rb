# Talks to Foreman (Twin Sun's process engine) as the signed-in person.
#
# The only POST is the sign-in exchange (/cli-auth/exchange), the same one
# Foreman's own CLI uses. Everything else is a GET on the administration API,
# so the ledger never changes anything in Foreman.
#
#   FOREMAN_URL  defaults to https://foreman.twinsun.dev
module ForemanApi
  TOOL_NAME = "factory-time-ledger".freeze

  def self.base_url = ENV.fetch("FOREMAN_URL", "https://foreman.twinsun.dev").to_s.chomp("/")

  # A token is good when one is stored and it hasn't expired.
  def self.signed_in?(setting = LedgerSetting.current)
    setting.foreman_token.present? && setting.foreman_token_expires_at.present? && setting.foreman_token_expires_at.future?
  end
end
