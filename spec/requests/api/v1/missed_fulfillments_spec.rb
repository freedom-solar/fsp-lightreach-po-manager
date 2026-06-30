require 'rails_helper'

RSpec.describe 'API V1 Missed Fulfillments', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'GET /api/v1/missed_fulfillments' do
    let(:report_data) do
      {
        generated_at: Time.current,
        count: 1,
        rows: [
          {
            project_number: '119002',
            customer: 'Jones',
            location: 'Houston',
            status_label: 'Partially Fulfilled',
            has_storage: true,
            installation_date: '2026-01-01',
            electrical_date: '2026-01-05',
            governing_basis: 'electrical',
            days_overdue: 42,
            netsuite_url: 'https://acct.app.netsuite.com/app/accounting/transactions/salesord.nl?id=2'
          }
        ]
      }
    end

    before do
      service = instance_double(MissedFulfillmentService)
      allow(MissedFulfillmentService).to receive(:new).and_return(service)
      allow(service).to receive(:report).and_return(report_data)
    end

    it 'returns the missed fulfillments payload' do
      get '/api/v1/missed_fulfillments'

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['count']).to eq(1)

      row = json['data']['rows'].first
      expect(row['project_number']).to eq('119002')
      expect(row['governing_basis']).to eq('electrical')
      expect(row['days_overdue']).to eq(42)
    end

    context 'when the service raises an error' do
      before do
        service = instance_double(MissedFulfillmentService)
        allow(MissedFulfillmentService).to receive(:new).and_return(service)
        allow(service).to receive(:report).and_raise(StandardError, 'NetSuite down')
      end

      it 'returns an internal server error' do
        get '/api/v1/missed_fulfillments'

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end
  end
end
