module Api
  module V1
    class ProcurementController < BaseController
      # GET /api/v1/procurement/open_pos
      # Open Contract Labor purchase orders grouped by Class + Location by vendor,
      # with pending-receipt and pending-bill flagged separately. Pulled live from
      # NetSuite via SuiteQL.
      def open_pos
        data = ProcurementDashboardService.new.dashboard
        render_success(data)
      rescue StandardError => e
        Rails.logger.error("Error fetching procurement dashboard: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to load procurement dashboard: #{e.message}", status: :internal_server_error)
      end
    end
  end
end
