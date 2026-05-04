require 'rails_helper'

RSpec.describe Api::V1::PoGenerationController, type: :controller do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'POST #generate_region' do
    let(:region) { 'Austin' }

    context 'when no job is running for region' do
      it 'creates a new job' do
        expect {
          post :generate_region, params: { region: region }
        }.to change(PoGenerationJob, :count).by(1)

        job = PoGenerationJob.last
        expect(job.job_type).to eq('region')
        expect(job.region).to eq(region)
        expect(job.user).to eq(user)
      end

      it 'enqueues the worker' do
        expect(BatchPoGenerationWorker).to receive(:perform_async)
        post :generate_region, params: { region: region }
      end

      it 'returns success response' do
        allow(BatchPoGenerationWorker).to receive(:perform_async)
        post :generate_region, params: { region: region }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['job_id']).to be_present
        expect(json['data']['message']).to include('started')
      end
    end

    context 'when job is already running for region' do
      before do
        create(:po_generation_job, :running, :region_job, region: region)
      end

      it 'does not create a new job' do
        expect {
          post :generate_region, params: { region: region }
        }.not_to change(PoGenerationJob, :count)
      end

      it 'returns conflict status' do
        post :generate_region, params: { region: region }
        expect(response).to have_http_status(:conflict)
      end

      it 'returns error message' do
        post :generate_region, params: { region: region }
        json = JSON.parse(response.body)
        expect(json['error']).to include('already running')
      end
    end

    context 'when user is not authenticated' do
      before do
        sign_out user
      end

      it 'redirects to sign in' do
        post :generate_region, params: { region: region }
        expect(response).to have_http_status(:found)
      end
    end

    context 'when region parameter is blank' do
      it 'returns bad request' do
        post :generate_region, params: { region: '' }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(PoGenerationJob).to receive(:running_for_region?).and_raise(StandardError, 'Unexpected error')
      end

      it 'returns internal server error' do
        post :generate_region, params: { region: region }
        expect(response).to have_http_status(:internal_server_error)
      end

      it 'includes error message in response' do
        post :generate_region, params: { region: region }
        json = JSON.parse(response.body)
        expect(json['error']).to include('Failed to start PO generation')
      end
    end
  end

  describe 'POST #generate_single' do
    let(:project_id) { 'SF-12345' }

    it 'creates a new job' do
      allow(PoGenerationWorker).to receive(:perform_async)
      expect {
        post :generate_single, params: { project_id: project_id }
      }.to change(PoGenerationJob, :count).by(1)

      job = PoGenerationJob.last
      expect(job.job_type).to eq('single')
      expect(job.user).to eq(user)
    end

    it 'enqueues the worker' do
      expect(PoGenerationWorker).to receive(:perform_async)
      post :generate_single, params: { project_id: project_id }
    end

    context 'when project is already being processed' do
      before do
        create(:po_generation_job, :running, project_ids: [project_id])
      end

      it 'returns conflict status' do
        post :generate_single, params: { project_id: project_id }
        expect(response).to have_http_status(:conflict)
      end

      it 'does not create a new job' do
        expect {
          post :generate_single, params: { project_id: project_id }
        }.not_to change(PoGenerationJob, :count)
      end

      it 'returns error message' do
        post :generate_single, params: { project_id: project_id }
        json = JSON.parse(response.body)
        expect(json['error']).to include('already running')
      end
    end

    it 'returns success response' do
      allow(PoGenerationWorker).to receive(:perform_async)
      post :generate_single, params: { project_id: project_id }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['job_id']).to be_present
    end

    context 'with skip_email parameter' do
      it 'creates job with skip_email set to true' do
        allow(PoGenerationWorker).to receive(:perform_async)
        post :generate_single, params: { project_id: project_id, skip_email: true }

        job = PoGenerationJob.last
        expect(job.skip_email).to be true
      end

      it 'passes skip_email to worker when true' do
        expect(PoGenerationWorker).to receive(:perform_async).with(anything, true)
        post :generate_single, params: { project_id: project_id, skip_email: 'true' }
      end

      it 'passes skip_email to worker when boolean true' do
        expect(PoGenerationWorker).to receive(:perform_async).with(anything, true)
        post :generate_single, params: { project_id: project_id, skip_email: true }
      end
    end

    context 'with skip_crew_check parameter' do
      it 'accepts skip_crew_check parameter' do
        allow(PoGenerationWorker).to receive(:perform_async)
        expect {
          post :generate_single, params: { project_id: project_id, skip_crew_check: true }
        }.not_to raise_error
      end
    end

    context 'when project_id is blank' do
      it 'returns bad request' do
        post :generate_single, params: { project_id: '' }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(PoGenerationJob).to receive(:locked_project_ids).and_raise(StandardError, 'Database error')
      end

      it 'returns internal server error' do
        post :generate_single, params: { project_id: project_id }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe 'POST #generate_batch' do
    let(:project_ids) { ['SF-001', 'SF-002', 'SF-003'] }

    context 'when no conflicts' do
      it 'creates a new job' do
        expect {
          post :generate_batch, params: { project_ids: project_ids }
        }.to change(PoGenerationJob, :count).by(1)

        job = PoGenerationJob.last
        expect(job.job_type).to eq('batch')
        expect(job.project_ids).to match_array(project_ids)
      end

      it 'enqueues the worker' do
        expect(BatchPoGenerationWorker).to receive(:perform_async)
        post :generate_batch, params: { project_ids: project_ids }
      end

      it 'returns success response' do
        allow(BatchPoGenerationWorker).to receive(:perform_async)
        post :generate_batch, params: { project_ids: project_ids }

        expect(response).to have_http_status(:success)
      end
    end

    context 'when some projects are locked' do
      before do
        running_job = create(:po_generation_job, :running, :batch_job, project_ids: ['SF-001'])
      end

      it 'does not create a new job' do
        expect {
          post :generate_batch, params: { project_ids: project_ids }
        }.not_to change(PoGenerationJob, :count)
      end

      it 'returns conflict status' do
        post :generate_batch, params: { project_ids: project_ids }
        expect(response).to have_http_status(:conflict)
      end

      it 'returns conflicting project IDs' do
        post :generate_batch, params: { project_ids: project_ids }
        json = JSON.parse(response.body)
        expect(json['data']['conflicting_projects']).to include('SF-001')
      end
    end

    context 'when project_ids is empty' do
      it 'returns bad request' do
        post :generate_batch, params: { project_ids: [] }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(PoGenerationJob).to receive(:locked_project_ids).and_raise(StandardError, 'Database error')
      end

      it 'returns internal server error' do
        post :generate_batch, params: { project_ids: project_ids }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe 'GET #job_status' do
    let(:job) { create(:po_generation_job, user: user) }

    it 'returns job status' do
      get :job_status, params: { id: job.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['job']['status']).to eq(job.status)
      expect(json['data']['job']['job_type']).to eq(job.job_type)
    end

    it 'includes logs' do
      create(:po_generation_log, po_generation_job: job, message: 'Test log', level: 'info')

      get :job_status, params: { id: job.id }

      json = JSON.parse(response.body)
      expect(json['data']['logs']).to be_an(Array)
      expect(json['data']['logs'].first['message']).to eq('Test log')
    end

    context 'when job does not exist' do
      it 'returns not found' do
        get :job_status, params: { id: 99999 }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when job belongs to different user' do
      let(:other_user) { create(:user, email: 'other@gofreedompower.com') }
      let(:other_job) { create(:po_generation_job, user: other_user) }

      it 'returns job status for any user' do
        get :job_status, params: { id: other_job.id }
        expect(response).to have_http_status(:success)
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(PoGenerationJob).to receive(:find).and_raise(StandardError, 'Database error')
      end

      it 'returns internal server error' do
        get :job_status, params: { id: job.id }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe 'POST #resend_email' do
    let(:job) { create(:po_generation_job, :completed_batch, user: user, successful_pos: 1) }

    before do
      allow_any_instance_of(EmailNotificationService).to receive(:send_batch_email)
    end

    it 'calls email notification service' do
      expect_any_instance_of(EmailNotificationService).to receive(:send_batch_email)
      post :resend_email, params: { job_id: job.id }
    end

    it 'returns success response' do
      post :resend_email, params: { job_id: job.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['message']).to include('Email resent')
    end

    context 'when job_id parameter is blank' do
      it 'returns bad request' do
        post :resend_email, params: { job_id: '' }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when job does not exist' do
      it 'returns not found' do
        post :resend_email, params: { job_id: 99999 }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when job is not completed' do
      let(:running_job) { create(:po_generation_job, :running, user: user) }

      it 'returns bad request' do
        post :resend_email, params: { job_id: running_job.id }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when job has no successful POs' do
      let(:failed_job) { create(:po_generation_job, :completed, user: user, successful_pos: 0) }

      it 'returns bad request' do
        post :resend_email, params: { job_id: failed_job.id }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when email fails' do
      before do
        allow_any_instance_of(EmailNotificationService).to receive(:send_batch_email).and_raise(StandardError, 'Email error')
      end

      it 'returns error response' do
        post :resend_email, params: { job_id: job.id }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end
end
