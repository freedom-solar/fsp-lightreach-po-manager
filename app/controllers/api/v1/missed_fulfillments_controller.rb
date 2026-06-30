module Api
  module V1
    class MissedFulfillmentsController < BaseController
      # GET /api/v1/missed_fulfillments
      # Sales Orders pending/partially fulfilled whose scheduled date (electrical
      # for energy-storage SOs, otherwise installation) is in the past.
      def index
        data = MissedFulfillmentService.new.report
        render_success(data)
      rescue StandardError => e
        Rails.logger.error("Error fetching missed fulfillments: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to load missed fulfillments: #{e.message}", status: :internal_server_error)
      end
    end
  end
end
