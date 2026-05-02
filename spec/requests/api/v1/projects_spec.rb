require 'rails_helper'

RSpec.describe 'API V1 Projects', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'GET /api/v1/projects/schedule/:region' do
    let(:region) { 'Austin' }
    let(:projects_data) do
      [
        {
          '_id' => 'SF-001',
          'name' => 'Austin Project 1',
          'fields' => {
            'system_size' => 10.5,
            'loan_application_id' => 'LOAN-001',
            'lightreach_direct_pay_po_link' => nil,
            'lender' => 'Lightreach'
          },
          'job_start' => '2025-03-15T10:00:00Z'
        }
      ]
    end

    before do
      job_schedule_service = instance_double(JobScheduleService)
      allow(JobScheduleService).to receive(:new).and_return(job_schedule_service)
      allow(job_schedule_service).to receive(:fetch_direct_pay_on_schedule).and_return(projects_data)
    end

    it 'returns projects for the region' do
      get "/api/v1/projects/schedule/#{region}"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['region']).to eq(region)
      expect(json['data']['projects'].length).to eq(1)
    end

    it 'includes all project fields' do
      get "/api/v1/projects/schedule/#{region}"

      json = JSON.parse(response.body)
      project = json['data']['projects'].first

      expect(project['id']).to eq('SF-001')
      expect(project['name']).to eq('Austin Project 1')
      expect(project['system_size']).to eq(10.5)
      expect(project['loan_application_id']).to eq('LOAN-001')
      expect(project['job_start']).to eq('2025-03-15T10:00:00Z')
      expect(project['has_po']).to be false
    end

    context 'when service raises error' do
      before do
        job_schedule_service = instance_double(JobScheduleService)
        allow(JobScheduleService).to receive(:new).and_return(job_schedule_service)
        allow(job_schedule_service).to receive(:fetch_direct_pay_on_schedule).and_raise(StandardError, 'API Error')
      end

      it 'returns internal server error' do
        get "/api/v1/projects/schedule/#{region}"

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to be_present
      end
    end
  end

  describe 'GET /api/v1/projects/:id' do
    let(:project_id) { 'SF-12345' }
    let(:project_data) do
      {
        '_id' => project_id,
        'name' => 'Test Project',
        'fields' => {
          'system_size' => 15.0,
          'loan_application_id' => 'LOAN-123',
          'lender' => 'Lightreach',
          'lightreach_direct_pay_po_link' => 'http://netsuite.com/po/12345',
          'market_region' => 'Austin'
        }
      }
    end

    before do
      allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ 'items' => [project_data] })
    end

    it 'returns project details' do
      get "/api/v1/projects/#{project_id}"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true

      project = json['data']['project']
      expect(project['id']).to eq(project_id)
      expect(project['name']).to eq('Test Project')
      expect(project['system_size']).to eq(15.0)
      expect(project['market_region']).to eq('Austin')
      expect(project['has_po']).to be true
    end

    context 'when project not found' do
      before do
        allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ 'items' => [] })
      end

      it 'returns not found' do
        get "/api/v1/projects/#{project_id}"

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Project not found')
      end
    end
  end
end
