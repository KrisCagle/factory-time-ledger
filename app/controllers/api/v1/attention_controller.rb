module Api
  module V1
    # POST /api/v1/attention — a heartbeat from a tool a person is working in.
    # Body: person_email, activity, and either jira_key or (source + batch_id).
    # Optional: at (ISO 8601, defaults to now).
    class AttentionController < BaseController
      def create
        person = Person.for_email!(params.require(:person_email), name: params[:person_name])
        activity = params.require(:activity).to_s
        raise ArgumentError, "activity must be one of #{Activity::ALL.join(', ')}" unless Activity::ALL.include?(activity)

        work_item = params[:jira_key].present? ? WorkItem.find_by!(jira_key: params[:jira_key].to_s.upcase) : nil
        batch = work_item ? nil : find_batch
        at = params[:at].present? ? Time.zone.parse(params[:at].to_s) : Time.current

        span = AttentionSpan.record_heartbeat!(person:, activity:, at:, work_item:, batch:)
        render json: { span_id: span.id, started_at: span.started_at, last_seen_at: span.last_seen_at }, status: :ok
      end

      private

        def find_batch
          return nil if params[:batch_id].blank?

          Batch.find_by!(source: params.require(:source), external_id: params[:batch_id].to_s)
        end
    end
  end
end
