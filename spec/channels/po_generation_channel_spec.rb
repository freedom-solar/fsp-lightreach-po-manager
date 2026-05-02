require 'rails_helper'

RSpec.describe PoGenerationChannel, type: :channel do
  let(:user) { create(:user) }
  let(:other_user) { create(:user, email: 'other@gofreedompower.com') }
  let(:job) { create(:po_generation_job, user: user, status: 'running') }

  before do
    stub_connection(current_user: user)
  end

  describe '#subscribed' do
    context 'with valid job_id' do
      it 'subscribes to the job stream' do
        subscribe(job_id: job.id)
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("po_generation_#{job.id}")
      end

      it 'transmits existing logs' do
        create(:po_generation_log, po_generation_job: job, message: 'Test log', level: 'info')
        create(:po_generation_log, po_generation_job: job, message: 'Another log', level: 'success')

        subscribe(job_id: job.id)

        expect(transmissions.length).to be >= 2
        log_transmissions = transmissions.select { |t| t[:message] }
        expect(log_transmissions.map { |t| t[:message] }).to include('Test log', 'Another log')
      end

      it 'transmits job status update' do
        subscribe(job_id: job.id)

        status_update = transmissions.find { |t| t[:type] == 'status_update' }
        expect(status_update).to be_present
        expect(status_update[:job_id]).to eq(job.id)
        expect(status_update[:status]).to eq('running')
        expect(status_update[:total_projects]).to eq(job.total_projects)
      end

      it 'includes timestamp in log transmissions' do
        log = create(:po_generation_log, po_generation_job: job, message: 'Test', level: 'info')
        subscribe(job_id: job.id)

        log_transmission = transmissions.find { |t| t[:message] == 'Test' }
        expect(log_transmission[:timestamp]).to be_present
        expect(log_transmission[:level]).to eq('info')
      end
    end

    context 'without job_id parameter' do
      it 'rejects the subscription' do
        subscribe
        expect(subscription).to be_rejected
      end
    end

    context 'with non-existent job_id' do
      it 'rejects the subscription' do
        subscribe(job_id: 99999)
        expect(subscription).to be_rejected
      end
    end

    context 'when job belongs to different user' do
      let(:other_job) { create(:po_generation_job, user: other_user) }

      it 'rejects the subscription' do
        subscribe(job_id: other_job.id)
        expect(subscription).to be_rejected
      end
    end

    context 'with completed job' do
      let(:completed_job) do
        create(:po_generation_job, :completed_batch, user: user, successful_pos: 5)
      end

      it 'transmits completed status' do
        subscribe(job_id: completed_job.id)

        status_update = transmissions.find { |t| t[:type] == 'status_update' }
        expect(status_update[:status]).to eq('completed')
        expect(status_update[:successful_pos]).to eq(5)
      end
    end
  end

  describe '#unsubscribed' do
    before do
      subscribe(job_id: job.id)
    end

    it 'stops all streams' do
      expect(subscription).to have_stream_from("po_generation_#{job.id}")
      perform :unsubscribed
      expect(subscription.streams).to be_empty
    end
  end

  describe 'real-time updates' do
    before do
      subscribe(job_id: job.id)
    end

    it 'receives broadcasts from the job stream' do
      expect {
        ActionCable.server.broadcast(
          "po_generation_#{job.id}",
          {
            timestamp: '10:00:00',
            level: 'info',
            message: 'New log entry',
            job_id: job.id
          }
        )
      }.to have_broadcasted_to("po_generation_#{job.id}")
    end
  end

  describe 'log ordering' do
    let!(:log1) { create(:po_generation_log, po_generation_job: job, message: 'First', level: 'info', created_at: 1.minute.ago) }
    let!(:log2) { create(:po_generation_log, po_generation_job: job, message: 'Second', level: 'info', created_at: 30.seconds.ago) }
    let!(:log3) { create(:po_generation_log, po_generation_job: job, message: 'Third', level: 'info', created_at: Time.current) }

    it 'transmits logs in chronological order' do
      subscribe(job_id: job.id)

      log_messages = transmissions.select { |t| t[:message] }.map { |t| t[:message] }
      expect(log_messages).to eq(['First', 'Second', 'Third'])
    end
  end
end
