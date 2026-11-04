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
    setting.assign_attributes(params.require(:ledger_setting).permit(:scarif_only_mine, :scarif_lookback_days))
    # A different set of items is wanted now, so the next sync looks back the full window.
    setting.scarif_last_synced_at = nil if setting.changed?
    if setting.save
      redirect_to settings_path(anchor: "scarif"), notice: "Scarif settings saved."
    else
      redirect_to settings_path(anchor: "scarif"), alert: setting.errors.full_messages.to_sentence
    end
  end
end
