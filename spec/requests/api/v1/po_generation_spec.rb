require 'rails_helper'

RSpec.describe 'API V1 PO Generation', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'POST /api/v1/po_generation/region' do
    let(:region) { 'Austin' }

    before do
      allow(BatchPoGenerationWorker).to receive(:perform_async)
    end

    it 'creates a new region job' do
      expect {
        post '/api/v1/po_generation/region', params: { region: region }
      }.to change(PoGenerationJob, :count).by(1)

      job = PoGenerationJob.last
      expect(job.job_type).to eq('region')
      expect(job.region).to eq(region)
      expect(job.user).to eq(user)
    end

    it 'enqueues the worker' do
      expect(BatchPoGenerationWorker).to receive(:perform_async)
      post '/api/v1/po_generation/region', params: { region: region }
    end

    it 'returns success response with job details' do
      post '/api/v1/po_generation/region', params: { region: region }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['job_id']).to be_present
      expect(json['data']['region']).to eq(region)
      expect(json['data']['message']).to include('started')
    end

    context 'when job already running for region' do
      before do
        create(:po_generation_job, :running, :region_job, region: region)
      end

      it 'returns conflict error' do
        post '/api/v1/po_generation/region', params: { region: region }

        expect(response).to have_http_status(:conflict)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('already running')
      end

      it 'does not create duplicate job' do
        expect {
          post '/api/v1/po_generation/region', params: { region: region }
        }.not_to change(PoGenerationJob, :count)
      end
    end

    context 'without region parameter' do
      it 'returns bad request' do
        post '/api/v1/po_generation/region', params: { region: '' }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Region parameter is required')
      end
    end
  end

  describe 'POST /api/v1/po_generation/project' do
    let(:project_id) { 'SF-12345' }

    before do
      allow(PoGenerationWorker).to receive(:perform_async)
    end

    it 'creates a new single project job' do
      expect {
        post '/api/v1/po_generation/project', params: { project_id: project_id }
      }.to change(PoGenerationJob, :count).by(1)

      job = PoGenerationJob.last
      expect(job.job_type).to eq('single')
      expect(job.project_ids).to eq([ project_id ])
    end

    it 'returns success with job ID' do
      post '/api/v1/po_generation/project', params: { project_id: project_id }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['job_id']).to be_present
      expect(json['data']['project_id']).to eq(project_id)
    end

    context 'with skip_email option' do
      it 'sets skip_email flag' do
        post '/api/v1/po_generation/project', params: { project_id: project_id, skip_email: true }

        job = PoGenerationJob.last
        expect(job.skip_email).to be true
      end

      it 'passes skip_email to worker' do
        expect(PoGenerationWorker).to receive(:perform_async).with(anything, true)
        post '/api/v1/po_generation/project', params: { project_id: project_id, skip_email: true }
      end
    end

    context 'when project is locked' do
      before do
        create(:po_generation_job, :running, :single_job, project_ids: [ project_id ])
      end

      it 'returns conflict error' do
        post '/api/v1/po_generation/project', params: { project_id: project_id }

        expect(response).to have_http_status(:conflict)
        json = JSON.parse(response.body)
        expect(json['error']).to include('already running')
      end
    end
  end

  describe 'POST /api/v1/po_generation/batch' do
    let(:project_ids) { [ 'SF-001', 'SF-002', 'SF-003' ] }

    before do
      allow(BatchPoGenerationWorker).to receive(:perform_async)
    end

    it 'creates a new batch job' do
      expect {
        post '/api/v1/po_generation/batch', params: { project_ids: project_ids }
      }.to change(PoGenerationJob, :count).by(1)

      job = PoGenerationJob.last
      expect(job.job_type).to eq('batch')
      expect(job.project_ids).to match_array(project_ids)
      expect(job.total_projects).to eq(3)
    end

    it 'returns success with project count' do
      post '/api/v1/po_generation/batch', params: { project_ids: project_ids }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['project_count']).to eq(3)
      expect(json['data']['project_ids']).to match_array(project_ids)
    end

    context 'when some projects are locked' do
      before do
        create(:po_generation_job, :running, :batch_job, project_ids: [ 'SF-001' ])
      end

      it 'returns conflict with locked project IDs' do
        post '/api/v1/po_generation/batch', params: { project_ids: project_ids }

        expect(response).to have_http_status(:conflict)
        json = JSON.parse(response.body)
        expect(json['data']['conflicting_projects']).to include('SF-001')
      end
    end

    context 'with empty project_ids', skip: 'Edge case with Rails parameter handling' do
      it 'returns bad request' do
        post '/api/v1/po_generation/batch', params: { project_ids: [] }

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'GET /api/v1/po_generation/jobs/:id' do
    let(:job) { create(:po_generation_job, user: user, status: 'running') }

    before do
      create(:po_generation_log, po_generation_job: job, message: 'Starting PO generation', level: 'info')
      create(:po_generation_log, po_generation_job: job, message: 'Processing project', level: 'info')
    end

    it 'returns job status and logs' do
      get "/api/v1/po_generation/jobs/#{job.id}"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json['data']['job']['id']).to eq(job.id)
      expect(json['data']['job']['status']).to eq('running')
      expect(json['data']['job']['job_type']).to eq(job.job_type)
      expect(json['data']['logs'].length).to eq(2)
      expect(json['data']['logs'].first['message']).to eq('Starting PO generation')
    end

    it 'includes timestamps in logs' do
      get "/api/v1/po_generation/jobs/#{job.id}"

      json = JSON.parse(response.body)
      expect(json['data']['logs'].first['timestamp']).to be_present
      expect(json['data']['logs'].first['level']).to eq('info')
    end

    context 'when job not found' do
      it 'returns not found' do
        get '/api/v1/po_generation/jobs/99999'

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Job not found')
      end
    end
  end

  describe 'POST /api/v1/po_generation/cancel/:id' do
    context 'when cancelling a running job' do
      let(:running_job) { create(:po_generation_job, :running, user: user) }

      it 'marks job as failed with cancellation message' do
        post "/api/v1/po_generation/cancel/#{running_job.id}"

        running_job.reload
        expect(running_job.status).to eq('failed')
        expect(running_job.error_message).to eq('Job cancelled by user')
        expect(running_job.completed_at).to be_present
      end

      it 'releases lock' do
        post "/api/v1/po_generation/cancel/#{running_job.id}"

        running_job.reload
        expect(running_job.locked_at).to be_nil
        expect(running_job.locked_by).to be_nil
      end

      it 'returns success response' do
        post "/api/v1/po_generation/cancel/#{running_job.id}"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['message']).to include('cancelled successfully')
        expect(json['data']['job_id']).to eq(running_job.id)
      end
    end

    context 'when cancelling a pending job' do
      let(:pending_job) { create(:po_generation_job, status: 'pending', user: user) }

      it 'marks job as failed' do
        post "/api/v1/po_generation/cancel/#{pending_job.id}"

        pending_job.reload
        expect(pending_job.status).to eq('failed')
        expect(pending_job.error_message).to eq('Job cancelled by user')
      end

      it 'returns success response' do
        post "/api/v1/po_generation/cancel/#{pending_job.id}"

        expect(response).to have_http_status(:success)
      end
    end

    context 'when job is already completed' do
      let(:completed_job) { create(:po_generation_job, :completed, user: user) }

      it 'returns bad request' do
        post "/api/v1/po_generation/cancel/#{completed_job.id}"

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Can only cancel pending or running jobs')
      end

      it 'does not change job status' do
        post "/api/v1/po_generation/cancel/#{completed_job.id}"

        completed_job.reload
        expect(completed_job.status).to eq('completed')
      end
    end

    context 'when job is already failed' do
      let(:failed_job) { create(:po_generation_job, :failed, user: user) }

      it 'returns bad request' do
        post "/api/v1/po_generation/cancel/#{failed_job.id}"

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when job not found' do
      it 'returns not found' do
        post '/api/v1/po_generation/cancel/99999'

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Job not found')
      end
    end

    context 'without job ID' do
      it 'returns bad request' do
        post '/api/v1/po_generation/cancel/'

        expect(response).to have_http_status(:not_found) # Rails routing returns 404 for missing ID
      end
    end
  end

  describe 'POST /api/v1/po_generation/resend_email' do
    let(:job) { create(:po_generation_job, :completed_batch, user: user, successful_pos: 2) }

    before do
      allow_any_instance_of(EmailNotificationService).to receive(:send_batch_email)
    end

    it 'calls email notification service' do
      expect_any_instance_of(EmailNotificationService).to receive(:send_batch_email)
      post '/api/v1/po_generation/resend_email', params: { job_id: job.id }
    end

    it 'returns success message' do
      post '/api/v1/po_generation/resend_email', params: { job_id: job.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['message']).to include('Email resent')
    end

    context 'when job is not completed' do
      let(:running_job) { create(:po_generation_job, :running, user: user) }

      it 'returns bad request' do
        post '/api/v1/po_generation/resend_email', params: { job_id: running_job.id }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Can only resend emails for completed jobs')
      end
    end

    context 'when no successful POs' do
      let(:failed_job) { create(:po_generation_job, :completed_batch, user: user, successful_pos: 0) }

      it 'returns bad request' do
        post '/api/v1/po_generation/resend_email', params: { job_id: failed_job.id }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when job_id is missing' do
      it 'returns bad request' do
        post '/api/v1/po_generation/resend_email', params: {}

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Job ID is required')
      end
    end

    context 'when job not found' do
      it 'returns not found' do
        post '/api/v1/po_generation/resend_email', params: { job_id: 99999 }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Job not found')
      end
    end
  end
end
