require 'rails_helper'

RSpec.describe 'API V1 Inventory', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'GET /api/v1/inventory/open_items' do
    let(:dashboard_data) do
      {
        generated_at: Time.current,
        count: 1,
        late_count: 1,
        rows: [
          {
            location: 'Houston',
            project_number: '100',
            project: '100 - Smith',
            item: 'Panel A',
            po_numbers: [ 'PO-1' ],
            ordered_qty: 10,
            received_qty: 6,
            allocated_qty: 2,
            not_received_qty: 4,
            received_not_allocated_qty: 4,
            install_date: '2026-07-01',
            region: 'Houston',
            urgency: 'overdue',
            late: true
          }
        ]
      }
    end

    before do
      service = instance_double(InventoryDashboardService)
      allow(InventoryDashboardService).to receive(:new).and_return(service)
      allow(service).to receive(:dashboard).and_return(dashboard_data)
    end

    it 'returns the inventory dashboard payload' do
      get '/api/v1/inventory/open_items'

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['count']).to eq(1)
      expect(json['data']['late_count']).to eq(1)

      row = json['data']['rows'].first
      expect(row['project']).to eq('100 - Smith')
      expect(row['not_received_qty']).to eq(4)
      expect(row['received_not_allocated_qty']).to eq(4)
      expect(row['urgency']).to eq('overdue')
    end

    context 'when the service raises an error' do
      before do
        service = instance_double(InventoryDashboardService)
        allow(InventoryDashboardService).to receive(:new).and_return(service)
        allow(service).to receive(:dashboard).and_raise(StandardError, 'NetSuite down')
      end

      it 'returns an internal server error' do
        get '/api/v1/inventory/open_items'

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end
  end
end
