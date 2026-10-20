# Heartbeats from the "Start working" button in the app itself. Factories and
# other tools use POST /api/v1/attention instead.
class AttentionController < ApplicationController
  before_action :require_person!

  def heartbeat
    activity = params[:activity].to_s
    return head :unprocessable_entity unless Activity::ALL.include?(activity)

    work_item = WorkItem.find_by(id: params[:work_item_id])
    batch = work_item ? nil : Batch.find_by(id: params[:batch_id])
    span = AttentionSpan.record_heartbeat!(person: current_person, activity:, work_item:, batch:)
    render json: { span_id: span.id, seconds: span.seconds }
  end
end
