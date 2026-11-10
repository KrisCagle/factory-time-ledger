# Signs the ledger in to Foreman as you, the way Foreman's own CLI does:
# Foreman's approval page (behind its Google sign-in) asks you to approve
# "factory-time-ledger", then sends your browser back to
# http://127.0.0.1:<this port>/callback with a one-time code, which the ledger
# trades (with a secret only it holds) for a token of up to 12 hours.
class ForemanConnectionsController < ApplicationController
  def sign_in
    setting = LedgerSetting.current
    verifier = ForemanApi::Client.new_verifier
    state = SecureRandom.hex(16)
    setting.update!(foreman_pending_verifier: verifier, foreman_pending_state: state)

    url = ForemanApi::Client.authorize_url(challenge: ForemanApi::Client.challenge_for(verifier), state:, port: request.port)
    redirect_to url, allow_other_host: true
  end

  # GET /callback?code=…&state=…  (the path Foreman sends the browser back to)
  def callback
    setting = LedgerSetting.current
    expected = setting.foreman_pending_state.to_s
    unless expected.present? && params[:code].present? && ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, expected)
      return redirect_to settings_path(anchor: "foreman"), alert: "That Foreman sign-in didn't match the one started here. Try Sign in to Foreman again."
    end

    issued = ForemanApi::Client.new(token: nil).exchange(code: params[:code], verifier: setting.foreman_pending_verifier)
    setting.update!(
      foreman_token: issued["token"], foreman_token_id: issued["id"].to_s, foreman_token_expires_at: Time.zone.parse(issued["expiresAt"].to_s),
      foreman_email: issued["email"], foreman_name: issued["name"], foreman_surface: issued["surface"],
      foreman_scopes: Array(issued["scopes"]), foreman_pending_verifier: nil, foreman_pending_state: nil, foreman_sync_error: nil
    )

    if setting.foreman_surface == "task_surface"
      redirect_to settings_path(anchor: "foreman"),
                  alert: "Signed in, but with \"task surface only\", which can't read process data. Sign in again and pick everything you can do."
    else
      ForemanApi::Poller.sync_in_background unless Rails.env.test?
      redirect_to settings_path(anchor: "foreman"),
                  notice: "Signed in to Foreman as #{setting.foreman_name || setting.foreman_email} until #{setting.foreman_token_expires_at.strftime('%-l:%M %p %b %-d')}. Reading your tickets' process data now."
    end
  rescue ForemanApi::Client::Error => e
    LedgerSetting.current.update!(foreman_pending_verifier: nil, foreman_pending_state: nil)
    redirect_to settings_path(anchor: "foreman"), alert: "Foreman sign-in didn't finish: #{e.message}"
  end

  # Forgets the token here. To end it in Foreman too, revoke it from Foreman's token list.
  def sign_out
    LedgerSetting.current.update!(foreman_token: nil, foreman_token_id: nil, foreman_token_expires_at: nil)
    redirect_to settings_path(anchor: "foreman"), notice: "Signed out of Foreman here. The token can also be revoked in Foreman's token list."
  end

  def sync
    return redirect_to(settings_path(anchor: "foreman"), alert: "Sign in to Foreman first.") unless ForemanApi.signed_in?

    if Rails.env.test?
      outcome = ForemanApi::Sync.call
      return redirect_to settings_path(anchor: "foreman"), (outcome.ok ? :notice : :alert) => outcome.message
    end

    notice = ForemanApi::Poller.sync_in_background ? "Reading from Foreman now; refresh in a minute." : "A Foreman refresh is already running."
    redirect_to settings_path(anchor: "foreman"), notice:
  end
end
