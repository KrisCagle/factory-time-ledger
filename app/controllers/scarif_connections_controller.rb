class ScarifConnectionsController < ApplicationController
  def check
    outcome = Scarif::CheckConnection.call
    redirect_to settings_path(anchor: "scarif"), (outcome.ok ? :notice : :alert) => outcome.message
  end

  def sync
    outcome = Scarif::Sync.call
    redirect_to settings_path(anchor: "scarif"), (outcome.ok ? :notice : :alert) => outcome.message
  end

  def update
    setting = LedgerSetting.current
    if setting.update(params.require(:ledger_setting).permit(:scarif_only_mine, :scarif_lookback_days))
      redirect_to settings_path(anchor: "scarif"), notice: "Scarif settings saved."
    else
      redirect_to settings_path(anchor: "scarif"), alert: setting.errors.full_messages.to_sentence
    end
  end
end
