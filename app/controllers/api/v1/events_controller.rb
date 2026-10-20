module Api
  module V1
    # POST /api/v1/events  — one event, or { "events": [...] } for several.
    class EventsController < BaseController
      def create
        payloads = params[:events].present? ? params.require(:events).map(&:to_unsafe_h) : [params.to_unsafe_h.except("controller", "action", "format", "event")]
        results = payloads.map { |payload| EventIngest.call(payload) }
        render json: {
          accepted: results.count { |r| !r.duplicate },
          duplicates: results.count(&:duplicate),
          event_ids: results.map { |r| r.event.external_id }
        }, status: :created
      end
    end
  end
end
