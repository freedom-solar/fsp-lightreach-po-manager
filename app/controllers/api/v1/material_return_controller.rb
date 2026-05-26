module Api
  module V1
    class MaterialReturnController < BaseController
      # POST /api/v1/material_return/request
      def create
        project_id = params[:project_id]
        message = params[:message]

        if project_id.blank?
          return render_error("Project ID is required", status: :bad_request)
        end

        if message.blank?
          return render_error("Return message is required", status: :bad_request)
        end

        # Fetch project data to get region and PO details
        project_data = fetch_project_data(project_id)

        unless project_data
          return render_error("Project not found or has no PO", status: :not_found)
        end

        # Send material return email
        MaterialReturnService.new.send_return_request(
          project_data: project_data,
          message: message,
          requester_email: current_user.email
        )

        render_success({
          message: "Material return request sent successfully",
          project_id: project_id
        })
      rescue StandardError => e
        Rails.logger.error("Error sending material return request: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to send material return request: #{e.message}", status: :internal_server_error)
      end

      private

      def fetch_project_data(project_id)
        fields = [
          "name",
          "fields.lightreach_direct_pay_po_link",
          "fields.loan_application_id",
          "fields.system_size",
          "fields.market_region"
        ]

        result = ProjectSunriseApi.get_projects_bulk([ project_id ], fields: fields)
        project = result["items"]&.first

        return nil unless project
        return nil unless project.dig("fields", "lightreach_direct_pay_po_link").present?

        # Extract PO ID from link
        po_link = project.dig("fields", "lightreach_direct_pay_po_link")
        po_id = extract_po_id_from_link(po_link)

        # Fetch PO details from NetSuite
        purchase_order = po_id.present? ? Netsuite::PurchaseOrder.find(po_id, raise_on_not_found: false) : nil

        {
          project_id: project["_id"],
          project_name: project["name"],
          po_id: po_id,
          po_link: po_link,
          region: location_name_for(purchase_order&.dig("location", "id")),
          system_size: project.dig("fields", "system_size"),
          loan_application_id: project.dig("fields", "loan_application_id"),
          po_items: extract_items_from_po(purchase_order)
        }
      end

      def extract_po_id_from_link(po_link)
        return nil if po_link.blank?

        match = po_link.match(/[?&]id=(\d+)/)
        match[1].to_i if match
      end

      def extract_items_from_po(purchase_order)
        return [] unless purchase_order

        items = purchase_order.dig("item", "items") || []
        items.map do |item|
          {
            description: item.dig("item", "refName") || item["description"],
            quantity: item["quantity"].to_i
          }
        end
      end

      def location_name_for(location_id)
        {
          1 => "Austin",
          2 => "Houston",
          3 => "Dallas",
          4 => "San Antonio",
          5 => "Denver",
          6 => "Co Springs",
          7 => "Tampa",
          17 => "Norfolk",
          18 => "Orlando",
          19 => "Charlotte",
          20 => "Raleigh",
          25 => "HQ",
          28 => "Commercial"
        }[location_id&.to_i] || "Unknown"
      end
    end
  end
end
