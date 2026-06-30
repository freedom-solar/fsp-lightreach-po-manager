module Api
  module V1
    class InventoryController < BaseController
      # GET /api/v1/inventory/open_items
      # Open inventory POs grouped by location -> project -> item, flagging
      # not-received, received-not-allocated, and late fulfillments (vs the
      # Skedulo install schedule). Pulled live from NetSuite + Skedulo.
      def open_items
        data = InventoryDashboardService.new.dashboard
        render_success(data)
      rescue StandardError => e
        Rails.logger.error("Error fetching inventory dashboard: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to load inventory dashboard: #{e.message}", status: :internal_server_error)
      end
    end
  end
end
