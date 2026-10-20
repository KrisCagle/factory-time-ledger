module Api
  module V1
    # Factories authenticate with the X-Ledger-Token header. If LEDGER_API_TOKEN
    # is blank, requests are accepted in development and test only.
    class BaseController < ActionController::API
      before_action :authenticate!

      rescue_from EventIngest::Invalid, ArgumentError do |error|
        render json: { error: error.message }, status: :unprocessable_entity
      end
      rescue_from ActiveRecord::RecordInvalid do |error|
        render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
      rescue_from ActiveRecord::RecordNotFound do |error|
        render json: { error: error.message }, status: :not_found
      end

      private

        def authenticate!
          expected = ENV["LEDGER_API_TOKEN"].to_s
          if expected.empty?
            return if Rails.env.local?

            render json: { error: "LEDGER_API_TOKEN is not configured" }, status: :service_unavailable
          else
            provided = request.headers["X-Ledger-Token"].to_s
            return if ActiveSupport::SecurityUtils.secure_compare(provided, expected)

            render json: { error: "invalid token" }, status: :unauthorized
          end
        end
    end
  end
end
