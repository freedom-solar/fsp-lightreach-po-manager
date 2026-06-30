require 'rails_helper'

RSpec.describe 'API V1 Procurement', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'GET /api/v1/procurement/open_pos' do
    let(:dashboard_data) do
      {
        generated_at: Time.current,
        count: 1,
        total_unbilled_amount: 150.0,
        rows: [
          {
            po_number: 'PO-100',
            netsuite_url: 'https://acct.app.netsuite.com/app/accounting/transactions/purchord.nl?id=100',
            vendor: 'Devlin',
            ns_class: 'Commercial',
            location: 'Austin',
            status_label: 'Partially Received',
            projects: [ 'C100 Foo' ],
            ordered_qty: 3,
            received_qty: 1,
            billed_qty: 1,
            amount: 250.0,
            unbilled_amount: 150.0,
            pending_receipt: true,
            pending_bill: true
          }
        ]
      }
    end

    before do
      service = instance_double(ProcurementDashboardService)
      allow(ProcurementDashboardService).to receive(:new).and_return(service)
      allow(service).to receive(:dashboard).and_return(dashboard_data)
    end

    it 'returns the procurement dashboard payload' do
      get '/api/v1/procurement/open_pos'

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['count']).to eq(1)
      expect(json['data']['total_unbilled_amount']).to eq(150.0)

      row = json['data']['rows'].first
      expect(row['po_number']).to eq('PO-100')
      expect(row['netsuite_url']).to include('purchord.nl?id=100')
      expect(row['vendor']).to eq('Devlin')
      expect(row['ns_class']).to eq('Commercial')
      expect(row['location']).to eq('Austin')
      expect(row['pending_receipt']).to be true
      expect(row['pending_bill']).to be true
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get '/api/v1/procurement/open_pos'
        expect(response).not_to have_http_status(:success)
      end
    end

    context 'when the service raises an error' do
      before do
        service = instance_double(ProcurementDashboardService)
        allow(ProcurementDashboardService).to receive(:new).and_return(service)
        allow(service).to receive(:dashboard).and_raise(StandardError, 'NetSuite down')
      end

      it 'returns an internal server error' do
        get '/api/v1/procurement/open_pos'

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to be_present
      end
    end
  end
end
