require 'rails_helper'

RSpec.describe PoGenerationJob, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should have_many(:po_generation_logs).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_inclusion_of(:job_type).in_array(%w[region batch single]) }
    it { should validate_inclusion_of(:status).in_array(%w[pending running completed failed]) }
  end

  describe 'attributes' do
    it 'has skip_email attribute with default false' do
      job = create(:po_generation_job)
      expect(job.skip_email).to eq(false)
    end

    it 'can set skip_email to true' do
      job = create(:po_generation_job, skip_email: true)
      expect(job.skip_email).to eq(true)
    end

    it 'stores project_ids as array' do
      job = create(:po_generation_job, project_ids: [ 'SF-001', 'SF-002' ])
      expect(job.project_ids).to be_an(Array)
      expect(job.project_ids).to contain_exactly('SF-001', 'SF-002')
    end

    it 'stores po_results as JSON' do
      results = [ { po_id: 12345, project_id: 'SF-001' } ]
      job = create(:po_generation_job, po_results: results)
      expect(job.po_results).to be_an(Array)
      expect(job.po_results.first['po_id']).to eq(12345)
    end
  end

  describe 'scopes' do
    let!(:pending_job) { create(:po_generation_job, status: 'pending') }
    let!(:running_job) { create(:po_generation_job, :running) }
    let!(:completed_job) { create(:po_generation_job, :completed) }

    describe '.running' do
      it 'returns only running jobs' do
        expect(PoGenerationJob.running).to contain_exactly(running_job)
      end
    end

    describe '.pending' do
      it 'returns only pending jobs' do
        expect(PoGenerationJob.pending).to contain_exactly(pending_job)
      end
    end

    describe '.completed' do
      it 'returns only completed jobs' do
        expect(PoGenerationJob.completed).to contain_exactly(completed_job)
      end
    end
  end

  describe '.running_for_region?' do
    let(:region) { 'NorCal' }

    context 'when there is a running job for the region' do
      let!(:running_job) { create(:po_generation_job, :region_job, :running, region: region) }

      it 'returns true' do
        expect(PoGenerationJob.running_for_region?(region)).to be true
      end
    end

    context 'when there is no running job for the region' do
      it 'returns false' do
        expect(PoGenerationJob.running_for_region?(region)).to be false
      end
    end

    context 'when there is a completed job for the region' do
      let!(:completed_job) { create(:po_generation_job, :region_job, :completed, region: region) }

      it 'returns false' do
        expect(PoGenerationJob.running_for_region?(region)).to be false
      end
    end
  end

  describe '.locked_project_ids' do
    context 'with multiple running jobs' do
      let!(:job1) { create(:po_generation_job, :running, project_ids: [ 'proj_1', 'proj_2' ]) }
      let!(:job2) { create(:po_generation_job, :running, project_ids: [ 'proj_3', 'proj_1' ]) }
      let!(:completed_job) { create(:po_generation_job, :completed, project_ids: [ 'proj_4' ]) }

      it 'returns unique project IDs from all running jobs' do
        locked_ids = PoGenerationJob.locked_project_ids
        expect(locked_ids).to match_array([ 'proj_1', 'proj_2', 'proj_3' ])
      end

      it 'does not include project IDs from completed jobs' do
        locked_ids = PoGenerationJob.locked_project_ids
        expect(locked_ids).not_to include('proj_4')
      end
    end

    context 'with no running jobs' do
      it 'returns an empty array' do
        expect(PoGenerationJob.locked_project_ids).to eq([])
      end
    end
  end

  describe '#acquire_lock!' do
    let(:job) { create(:po_generation_job) }
    let(:worker_id) { 'worker_123' }

    it 'updates job to running status' do
      job.acquire_lock!(worker_id)
      expect(job.reload.status).to eq('running')
    end

    it 'sets locked_at timestamp' do
      job.acquire_lock!(worker_id)
      expect(job.reload.locked_at).to be_present
    end

    it 'sets locked_by worker ID' do
      job.acquire_lock!(worker_id)
      expect(job.reload.locked_by).to eq(worker_id)
    end

    it 'sets started_at timestamp' do
      job.acquire_lock!(worker_id)
      expect(job.reload.started_at).to be_present
    end
  end

  describe '#release_lock!' do
    let(:job) { create(:po_generation_job, :running) }

    it 'clears locked_at' do
      job.release_lock!
      expect(job.reload.locked_at).to be_nil
    end

    it 'clears locked_by' do
      job.release_lock!
      expect(job.reload.locked_by).to be_nil
    end
  end

  describe '#completed?' do
    it 'returns true when status is completed' do
      job = create(:po_generation_job, :completed)
      expect(job.completed?).to be true
    end

    it 'returns false when status is not completed' do
      job = create(:po_generation_job, status: 'running')
      expect(job.completed?).to be false
    end
  end

  describe '#failed?' do
    it 'returns true when status is failed' do
      job = create(:po_generation_job, :failed)
      expect(job.failed?).to be true
    end

    it 'returns false when status is not failed' do
      job = create(:po_generation_job, status: 'completed')
      expect(job.failed?).to be false
    end
  end

  describe '#running?' do
    it 'returns true when status is running' do
      job = create(:po_generation_job, :running)
      expect(job.running?).to be true
    end

    it 'returns false when status is not running' do
      job = create(:po_generation_job, status: 'completed')
      expect(job.running?).to be false
    end
  end

  describe '#pending?' do
    it 'returns true when status is pending' do
      job = create(:po_generation_job, status: 'pending')
      expect(job.pending?).to be true
    end

    it 'returns false when status is not pending' do
      job = create(:po_generation_job, status: 'running')
      expect(job.pending?).to be false
    end
  end

  describe '#cancelled?' do
    it 'returns true when job is failed with cancellation message' do
      job = create(:po_generation_job, status: 'failed', error_message: 'Job cancelled by user')
      expect(job.cancelled?).to be true
    end

    it 'returns false when job is failed with different error message' do
      job = create(:po_generation_job, status: 'failed', error_message: 'Some other error')
      expect(job.cancelled?).to be false
    end

    it 'returns false when job is not failed' do
      job = create(:po_generation_job, status: 'completed')
      expect(job.cancelled?).to be false
    end
  end

  describe 'status helpers' do
    it 'identifies pending jobs' do
      job = create(:po_generation_job, status: 'pending')
      expect(job.completed?).to be false
      expect(job.failed?).to be false
    end

    it 'identifies running jobs' do
      job = create(:po_generation_job, :running)
      expect(job.completed?).to be false
      expect(job.failed?).to be false
    end
  end

  describe 'timestamps' do
    it 'sets created_at on creation' do
      job = create(:po_generation_job)
      expect(job.created_at).to be_present
    end

    it 'updates updated_at on changes' do
      job = create(:po_generation_job)
      original_time = job.updated_at
      sleep 0.01
      job.update(status: 'running')
      expect(job.updated_at).to be > original_time
    end
  end

  describe 'edge cases' do
    describe '.locked_project_ids with nil project_ids' do
      it 'handles jobs with nil project_ids' do
        create(:po_generation_job, :running, project_ids: nil)
        create(:po_generation_job, :running, project_ids: [ 'proj_1' ])

        locked_ids = PoGenerationJob.locked_project_ids
        expect(locked_ids).to eq([ 'proj_1' ])
      end
    end

    describe '.running_for_region? with nil region' do
      it 'returns true when job with nil region exists' do
        create(:po_generation_job, :running, region: nil)
        expect(PoGenerationJob.running_for_region?(nil)).to be true
      end

      it 'handles empty region string' do
        create(:po_generation_job, :running, region: '')
        expect(PoGenerationJob.running_for_region?('')).to be true
      end
    end

    describe 'status transitions' do
      it 'can transition from pending to running to completed' do
        job = create(:po_generation_job, status: 'pending')
        expect(job).not_to be_completed
        expect(job).not_to be_failed

        job.update(status: 'running')
        expect(job).not_to be_completed

        job.update(status: 'completed')
        expect(job).to be_completed
      end

      it 'can transition to failed status' do
        job = create(:po_generation_job, status: 'running')
        job.update(status: 'failed')
        expect(job).to be_failed
        expect(job).not_to be_completed
      end
    end

    describe '#acquire_lock! with different worker IDs' do
      it 'updates lock with new worker ID' do
        job = create(:po_generation_job)
        job.acquire_lock!('worker_1')
        expect(job.reload.locked_by).to eq('worker_1')

        job.acquire_lock!('worker_2')
        expect(job.reload.locked_by).to eq('worker_2')
      end
    end

    describe '#release_lock! on unlocked job' do
      it 'safely handles releasing lock on already unlocked job' do
        job = create(:po_generation_job)
        expect { job.release_lock! }.not_to raise_error
        expect(job.reload.locked_at).to be_nil
      end
    end
  end
end
