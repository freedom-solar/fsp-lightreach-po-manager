require 'rails_helper'

RSpec.describe BatchPoGenerationWorker, type: :worker do
  let(:user) { create(:user) }
  let(:service) { instance_double(PoGenerationService) }

  before do
    allow(PoGenerationService).to receive(:new).and_return(service)
    allow(service).to receive(:log_progress)
  end

  describe 'region job' do
    let(:job) { create(:po_generation_job, :region_job, region: 'Austin', user: user) }
    let(:po_results) do
      [
        { 'po_id' => 12345, 'project_id' => 'SF-001', 'account_id' => 123 },
        { 'po_id' => 12346, 'project_id' => 'SF-002', 'account_id' => 124 }
      ]
    end

    before do
      allow(service).to receive(:generate_pos_for_region).and_return(po_results)
      allow(EmailNotificationService).to receive(:new).and_return(instance_double(EmailNotificationService, send_batch_email: true))
    end

    it 'updates job status to running' do
      described_class.new.perform(job.id)
      job.reload
      expect(job.started_at).to be_present
      expect(job.locked_at).to be_nil
      expect(job.locked_by).to be_nil
    end

    it 'generates POs for region' do
      expect(service).to receive(:generate_pos_for_region).with('Austin')
      described_class.new.perform(job.id)
    end

    it 'updates job with successful results' do
      described_class.new.perform(job.id)
      job.reload

      expect(job.status).to eq('completed')
      expect(job.successful_pos).to eq(2)
      expect(job.po_results).to be_present
      expect(job.completed_at).to be_present
    end

    it 'sends email notification' do
      email_service = instance_double(EmailNotificationService)
      allow(EmailNotificationService).to receive(:new).with(job).and_return(email_service)

      expect(email_service).to receive(:send_batch_email)
      described_class.new.perform(job.id)
    end

    it 'logs progress' do
      expect(service).to receive(:log_progress).with(/Starting PO generation/)
      expect(service).to receive(:log_progress).with(/Job completed/, level: :success)
      described_class.new.perform(job.id)
    end
  end

  describe 'single project job' do
    let(:project_id) { 'SF-12345' }
    let(:job) do
      create(:po_generation_job, :single_job, project_ids: [project_id], user: user)
    end
    let(:po_result) { { 'po_id' => 12345, 'project_id' => project_id } }

    before do
      allow(service).to receive(:generate_po_for_project).and_return(po_result)
      allow(EmailNotificationService).to receive(:new).and_return(instance_double(EmailNotificationService, send_batch_email: true))
    end

    it 'generates PO for single project' do
      expect(service).to receive(:generate_po_for_project).with(project_id)
      described_class.new.perform(job.id)
    end

    it 'updates job with result' do
      described_class.new.perform(job.id)
      job.reload

      expect(job.status).to eq('completed')
      expect(job.successful_pos).to eq(1)
    end

    context 'when project_id is nil' do
      let(:job) do
        create(:po_generation_job, :single_job, project_ids: nil, user: user)
      end

      it 'logs error' do
        expect(service).to receive(:log_progress).with(/No project ID provided/, level: :error)
        described_class.new.perform(job.id)
      end

      it 'completes with zero successful POs' do
        described_class.new.perform(job.id)
        job.reload
        expect(job.successful_pos).to eq(0)
      end
    end

    context 'when generation fails' do
      before do
        allow(service).to receive(:generate_po_for_project).and_return(nil)
      end

      it 'completes with zero results' do
        described_class.new.perform(job.id)
        job.reload
        expect(job.successful_pos).to eq(0)
      end

      it 'does not send email' do
        expect_any_instance_of(EmailNotificationService).not_to receive(:send_batch_email)
        described_class.new.perform(job.id)
      end
    end
  end

  describe 'batch job' do
    let(:project_ids) { ['SF-001', 'SF-002', 'SF-003'] }
    let(:job) do
      create(:po_generation_job, :batch_job, project_ids: project_ids, user: user)
    end
    let(:po_results) do
      [
        { 'po_id' => 12345, 'project_id' => 'SF-001' },
        { 'po_id' => 12346, 'project_id' => 'SF-002' }
      ]
    end

    before do
      allow(service).to receive(:generate_pos_for_batch).and_return(po_results)
      allow(EmailNotificationService).to receive(:new).and_return(instance_double(EmailNotificationService, send_batch_email: true))
    end

    it 'generates POs for batch' do
      expect(service).to receive(:generate_pos_for_batch).with(project_ids)
      described_class.new.perform(job.id)
    end

    it 'updates job with results' do
      described_class.new.perform(job.id)
      job.reload

      expect(job.status).to eq('completed')
      expect(job.successful_pos).to eq(2)
      expect(job.failed_pos).to eq(1)
    end
  end

  describe 'error handling' do
    let(:job) { create(:po_generation_job, :region_job, region: 'Austin', user: user) }

    before do
      allow(service).to receive(:generate_pos_for_region).and_raise(StandardError, 'Test error')
    end

    it 'updates job status to failed' do
      expect { described_class.new.perform(job.id) }.to raise_error(StandardError)
      job.reload

      expect(job.status).to eq('failed')
      expect(job.error_message).to eq('Test error')
      expect(job.completed_at).to be_present
    end

    it 'logs error' do
      expect(service).to receive(:log_progress).with(/Job failed/, level: :error)
      expect { described_class.new.perform(job.id) }.to raise_error(StandardError)
    end

    it 'releases lock' do
      expect { described_class.new.perform(job.id) }.to raise_error(StandardError)
      job.reload

      expect(job.locked_at).to be_nil
      expect(job.locked_by).to be_nil
    end
  end


  describe 'email notification' do
    let(:job) { create(:po_generation_job, :region_job, region: 'Austin', user: user) }
    let(:email_service) { instance_double(EmailNotificationService) }

    context 'when POs are generated' do
      let(:po_results) { [{ 'po_id' => 12345 }] }

      before do
        allow(service).to receive(:generate_pos_for_region).and_return(po_results)
        allow(EmailNotificationService).to receive(:new).with(job).and_return(email_service)
      end

      it 'sends email notification' do
        expect(email_service).to receive(:send_batch_email)
        described_class.new.perform(job.id)
      end

      it 'logs email notification' do
        allow(email_service).to receive(:send_batch_email)
        expect(service).to receive(:log_progress).with(/Sending email/)
        described_class.new.perform(job.id)
      end
    end

    context 'when no POs are generated' do
      before do
        allow(service).to receive(:generate_pos_for_region).and_return([])
      end

      it 'does not send email' do
        expect(EmailNotificationService).not_to receive(:new)
        described_class.new.perform(job.id)
      end
    end
  end
end
