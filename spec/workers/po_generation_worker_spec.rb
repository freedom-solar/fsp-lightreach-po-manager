require 'rails_helper'

RSpec.describe PoGenerationWorker, type: :worker do
  let(:user) { create(:user) }
  let(:project_id) { 'SF-12345' }
  let(:job) do
    create(:po_generation_job, :single_job, project_ids: [project_id], user: user)
  end
  let(:service) { instance_double(PoGenerationService) }
  let(:email_service) { instance_double(EmailNotificationService) }

  before do
    allow(PoGenerationService).to receive(:new).and_return(service)
    allow(EmailNotificationService).to receive(:new).and_return(email_service)
  end

  describe '#perform' do
    let(:po_result) do
      {
        'po_id' => 12345,
        'project_id' => project_id,
        'account_id' => 123
      }
    end

    before do
      allow(service).to receive(:generate_po_for_project).and_return(po_result)
      allow(email_service).to receive(:send_batch_email)
    end

    it 'updates job status to running' do
      described_class.new.perform(job.id)
      job.reload
      expect(job.started_at).to be_present
      expect(job.locked_at).to be_nil
      expect(job.locked_by).to be_nil
    end

    it 'generates PO for project' do
      expect(service).to receive(:generate_po_for_project).with(project_id, skip_email: false)
      described_class.new.perform(job.id)
    end

    it 'updates job with successful result' do
      described_class.new.perform(job.id)
      job.reload

      expect(job.status).to eq('completed')
      expect(job.successful_pos).to eq(1)
      expect(job.po_results).to eq([po_result])
      expect(job.completed_at).to be_present
    end

    it 'sends email notification' do
      expect(email_service).to receive(:send_batch_email)
      described_class.new.perform(job.id)
    end

    context 'with skip_email option' do
      it 'does not send email when skip_email is true' do
        expect(email_service).not_to receive(:send_batch_email)
        described_class.new.perform(job.id, skip_email: true)
      end

      it 'passes skip_email to service' do
        expect(service).to receive(:generate_po_for_project).with(project_id, skip_email: true)
        described_class.new.perform(job.id, skip_email: true)
      end
    end

    context 'when PO generation fails' do
      before do
        allow(service).to receive(:generate_po_for_project).and_return(nil)
      end

      it 'updates job status to failed' do
        described_class.new.perform(job.id)
        job.reload

        expect(job.status).to eq('failed')
        expect(job.failed_pos).to eq(1)
        expect(job.error_message).to eq('Failed to create PO')
      end

      it 'does not send email' do
        expect(email_service).not_to receive(:send_batch_email)
        described_class.new.perform(job.id)
      end
    end
  end

  describe 'error handling' do
    before do
      allow(service).to receive(:generate_po_for_project).and_raise(StandardError, 'Test error')
    end

    it 'updates job status to failed' do
      expect { described_class.new.perform(job.id) }.to raise_error(StandardError)
      job.reload

      expect(job.status).to eq('failed')
      expect(job.error_message).to eq('Test error')
      expect(job.completed_at).to be_present
    end

    it 'releases lock' do
      expect { described_class.new.perform(job.id) }.to raise_error(StandardError)
      job.reload

      expect(job.locked_at).to be_nil
      expect(job.locked_by).to be_nil
    end

    it 're-raises the error' do
      expect { described_class.new.perform(job.id) }.to raise_error(StandardError, 'Test error')
    end
  end

  describe 'lock management' do
    let(:worker) { described_class.new }
    let(:jid) { 'test-job-id' }

    before do
      allow(worker).to receive(:jid).and_return(jid)
      allow(service).to receive(:generate_po_for_project).and_return({})
      allow(email_service).to receive(:send_batch_email)
    end

    it 'locks job during processing' do
      called = false
      allow(service).to receive(:generate_po_for_project) do
        job.reload
        expect(job.locked_at).to be_present
        expect(job.locked_by).to eq(jid)
        called = true
        {}
      end

      worker.perform(job.id)
      expect(called).to be true
    end

    it 'releases lock after completion' do
      worker.perform(job.id)
      job.reload

      expect(job.locked_at).to be_nil
      expect(job.locked_by).to be_nil
    end

    it 'releases lock on error' do
      allow(service).to receive(:generate_po_for_project).and_raise(StandardError)

      expect { worker.perform(job.id) }.to raise_error(StandardError)
      job.reload

      expect(job.locked_at).to be_nil
      expect(job.locked_by).to be_nil
    end
  end
end
