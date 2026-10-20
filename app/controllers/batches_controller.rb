class BatchesController < ApplicationController
  def index
    @batches = Batch.includes(:started_by, work_items: :agent_runs).order(started_at: :desc)
  end

  def show
    @batch = Batch.find(params[:id])
    @items = @batch.work_items.includes(:agent_runs, :time_drafts).order(:jira_key)
    @overhead_spans = @batch.attention_spans.includes(:person).order(:started_at)
    @setting = LedgerSetting.current
    engine_items = @items.map { |i| Attribution::Item.new(id: i.id, batch_id: @batch.id, agent_points: i.agent_points, agent_seconds: i.agent_seconds) }
    # A one-second probe pool shows how any overhead would split right now.
    probe = Attribution::Span.new(id: 0, batch_id: @batch.id, activity: "supervision", started_at: Time.current, ended_at: Time.current + 3600)
    @split = Attribution::Engine.call(spans: [probe], items: engine_items, rule: @setting.split_rule).batch_splits.first
  end
end
