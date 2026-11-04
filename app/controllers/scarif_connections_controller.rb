class ScarifConnectionsController < ApplicationController
  def check
    outcome = Scarif::CheckConnection.call
    redirect_to settings_path(anchor: "scarif"), (outcome.ok ? :notice : :alert) => outcome.message
  end

  def sync
    unless Scarif::Client.configured?
      return redirect_to settings_path(anchor: "scarif"), alert: "Scarif isn't connected. Add SCARIF_API_TOKEN to .env and restart."
    end

    if Rails.env.test?
      outcome = Scarif::Sync.call
      return redirect_to settings_path(anchor: "scarif"), (outcome.ok ? :notice : :alert) => outcome.message
    end

    notice = if Scarif::Poller.sync_in_background
               "Sync started. The first one can take a few minutes; refresh this page to see progress."
             else
               "A sync is already running. Refresh this page to see progress."
             end
    redirect_to settings_path(anchor: "scarif"), notice:
  end

  def update
    setting = LedgerSetting.current
    setting.assign_attributes(params.require(:ledger_setting).permit(:scarif_only_mine, :scarif_lookback_days))
    # A different set of items is wanted now, so the next sync looks back the full window.
    changed = setting.changed?
    setting.scarif_last_synced_at = nil if changed
    if setting.save
      # Re-decide which items are yours under the new settings.
      ExternalRecord.where(source: Scarif::Sync::SOURCE, work_item_id: nil).delete_all if changed
      redirect_to settings_path(anchor: "scarif"), notice: "Scarif settings saved."
    else
      redirect_to settings_path(anchor: "scarif"), alert: setting.errors.full_messages.to_sentence
    end
  end
end
