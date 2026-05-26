require "rails_helper"

RSpec.describe "API V1 Material Return", type: :request do
  let(:user) { create(:user) }
  let(:project_id) { "SF-12345" }
  let(:message) { "Customer cancelled, need to return panels" }

  before do
    sign_in user
  end

  describe "POST /api/v1/material_return/request" do
    let(:project_data) do
      {
        "items" => [ {
          "_id" => project_id,
          "name" => "Test Project",
          "fields" => {
            "lightreach_direct_pay_po_link" => "https://system.netsuite.com/app/accounting/transactions/purchord.nl?id=12345",
            "system_size" => 10.5,
            "loan_application_id" => "loan-123"
          }
        } ]
      }
    end

    let(:purchase_order) do
      {
        "location" => { "id" => 1 },
        "item" => {
          "items" => [
            { "item" => { "refName" => "Solar Panel" }, "quantity" => 20 },
            { "item" => { "refName" => "Inverter" }, "quantity" => 1 }
          ]
        }
      }
    end

    before do
      allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return(project_data)
      allow(Netsuite::PurchaseOrder).to receive(:find).and_return(purchase_order)
      allow(DistributionList).to receive(:warehouse).and_return([ "warehouse@example.com" ])
      allow(DistributionList).to receive(:regional_rom).and_return([ "rom@example.com" ])
    end

    it "sends material return request" do
      expect(Lightreach::DirectPayMailer).to receive(:material_return_requested)
        .with(hash_including(
          project_data: hash_including(
            project_id: project_id,
            project_name: "Test Project",
            region: "Austin"
          ),
          return_message: message,
          requester_email: user.email
        ))
        .and_call_original

      post "/api/v1/material_return/request", params: { project_id: project_id, message: message }
      expect(response).to have_http_status(:success)
    end

    it "returns success response" do
      post "/api/v1/material_return/request", params: { project_id: project_id, message: message }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["data"]["message"]).to include("Material return request sent successfully")
      expect(json["data"]["project_id"]).to eq(project_id)
    end

    context "when project_id is blank" do
      it "returns bad request" do
        post "/api/v1/material_return/request", params: { project_id: "", message: message }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("Project ID is required")
      end
    end

    context "when message is blank" do
      it "returns bad request" do
        post "/api/v1/material_return/request", params: { project_id: project_id, message: "" }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("Return message is required")
      end
    end

    context "when project is not found" do
      before do
        allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ "items" => [] })
      end

      it "returns not found" do
        post "/api/v1/material_return/request", params: { project_id: project_id, message: message }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("Project not found or has no PO")
      end
    end

    context "when project has no PO" do
      let(:project_data_no_po) do
        {
          "items" => [ {
            "_id" => project_id,
            "name" => "Test Project",
            "fields" => {}
          } ]
        }
      end

      before do
        allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return(project_data_no_po)
      end

      it "returns not found" do
        post "/api/v1/material_return/request", params: { project_id: project_id, message: message }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("Project not found or has no PO")
      end
    end

    context "when user is not authenticated" do
      before do
        sign_out user
      end

      it "redirects to sign in" do
        post "/api/v1/material_return/request", params: { project_id: project_id, message: message }
        expect(response).to have_http_status(:found)
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_raise(StandardError, "API error")
      end

      it "returns internal server error" do
        post "/api/v1/material_return/request", params: { project_id: project_id, message: message }
        expect(response).to have_http_status(:internal_server_error)
      end

      it "includes error message in response" do
        post "/api/v1/material_return/request", params: { project_id: project_id, message: message }
        json = JSON.parse(response.body)
        expect(json["error"]).to include("Failed to send material return request")
      end
    end
  end
end
