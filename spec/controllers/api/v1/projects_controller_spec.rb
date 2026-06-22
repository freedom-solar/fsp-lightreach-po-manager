require 'rails_helper'

RSpec.describe Api::V1::ProjectsController, type: :controller do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'GET #schedule_by_region' do
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
        },
        {
          '_id' => 'SF-002',
          'name' => 'Austin Project 2',
          'fields' => {
            'system_size' => 12.0,
            'loan_application_id' => 'LOAN-002',
            'lightreach_direct_pay_po_link' => 'existing-po',
            'lender' => 'Lightreach'
          },
          'job_start' => '2025-03-20T10:00:00Z'
        }
      ]
    end

    before do
      job_schedule_service = instance_double(JobScheduleService)
      allow(JobScheduleService).to receive(:new).and_return(job_schedule_service)
      allow(job_schedule_service).to receive(:fetch_jobs_on_schedule).and_return(projects_data)
    end

    it 'returns success response' do
      get :schedule_by_region, params: { region: region }
      expect(response).to have_http_status(:success)
    end

    it 'returns projects data' do
      get :schedule_by_region, params: { region: region }
      json = JSON.parse(response.body)
      expect(json['data']['projects']).to be_an(Array)
      expect(json['data']['projects'].length).to eq(2)
    end

    it 'transforms project data correctly' do
      get :schedule_by_region, params: { region: region }
      json = JSON.parse(response.body)

      project = json['data']['projects'].first
      expect(project['id']).to eq('SF-001')
      expect(project['name']).to eq('Austin Project 1')
      expect(project['system_size']).to eq(10.5)
      expect(project['job_start']).to eq('2025-03-15T10:00:00Z')
      expect(project['has_po']).to be false
    end

    it 'identifies projects with existing POs' do
      get :schedule_by_region, params: { region: region }
      json = JSON.parse(response.body)

      project_with_po = json['data']['projects'].find { |p| p['id'] == 'SF-002' }
      expect(project_with_po['has_po']).to be true
    end

    context 'when service raises error' do
      before do
        job_schedule_service = instance_double(JobScheduleService)
        allow(JobScheduleService).to receive(:new).and_return(job_schedule_service)
        allow(job_schedule_service).to receive(:fetch_jobs_on_schedule).and_raise(StandardError, 'API Error')
      end

      it 'returns error response' do
        get :schedule_by_region, params: { region: region }
        expect(response).to have_http_status(:internal_server_error)
      end

      it 'returns error message' do
        get :schedule_by_region, params: { region: region }
        json = JSON.parse(response.body)
        expect(json['error']).to be_present
      end
    end

    context 'when user is not authenticated' do
      before do
        sign_out user
      end

      it 'redirects to sign in' do
        get :schedule_by_region, params: { region: region }
        expect(response).to have_http_status(:found)
      end
    end

    context 'when region parameter is missing' do
      it 'returns bad request' do
        get :schedule_by_region, params: { region: '' }
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'GET #show' do
    let(:project_id) { 'SF-12345' }
    let(:project_data) do
      {
        '_id' => project_id,
        'name' => 'Test Project',
        'fields' => {
          'system_size' => 15.0,
          'loan_application_id' => 'LOAN-123',
          'lender' => 'Lightreach',
          'lightreach_direct_pay_po_link' => nil,
          'market_region' => 'Austin'
        }
      }
    end

    before do
      allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ 'items' => [ project_data ] })
    end

    it 'returns success response' do
      get :show, params: { id: project_id }
      expect(response).to have_http_status(:success)
    end

    it 'returns project data' do
      get :show, params: { id: project_id }
      json = JSON.parse(response.body)
      expect(json['data']['project']).to be_present
      expect(json['data']['project']['id']).to eq(project_id)
      expect(json['data']['project']['name']).to eq('Test Project')
    end

    context 'when project not found' do
      before do
        allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ 'items' => [] })
      end

      it 'returns not found status' do
        get :show, params: { id: project_id }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_raise(StandardError, 'API Error')
      end

      it 'returns internal server error' do
        get :show, params: { id: project_id }
        expect(response).to have_http_status(:internal_server_error)
      end

      it 'returns error message' do
        get :show, params: { id: project_id }
        json = JSON.parse(response.body)
        expect(json['error']).to include('Failed to fetch project')
      end
    end

    context 'when user is not authenticated' do
      before do
        sign_out user
      end

      it 'redirects to sign in' do
        get :show, params: { id: project_id }
        expect(response).to have_http_status(:found)
      end
    end
  end
end
