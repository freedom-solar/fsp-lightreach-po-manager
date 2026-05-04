require 'rails_helper'

RSpec.describe EmailNotificationService, type: :service do
  let(:job) { create(:po_generation_job, :completed_batch) }
  let(:service) { described_class.new(job) }
  let(:mock_pdf_binary) { "PDF_BINARY_CONTENT" }

  before do
    # Mock NetSuite PDF fetching
    allow(Netsuite::PurchaseOrder).to receive(:fetch_pdf_binary).and_return(mock_pdf_binary)
  end

  describe '#send_batch_email' do
    let(:po_results) do
      [
        {
          po_id: 12345,
          project_id: 'SF-001',
          project_name: 'Austin Project 1',
          location_name: 'Austin',
          lightreach_account_id: 'LR-123',
          po_items: [
            { part_number: 'PSR-B168', quantity: 10, category: 3, description: 'Racking' }
          ],
          job_start: '2025-02-01'
        },
        {
          po_id: 12346,
          project_id: 'SF-002',
          project_name: 'Dallas Project 1',
          location_name: 'Dallas',
          lightreach_account_id: 'LR-124',
          po_items: [
            { part_number: 'MODULE-123', quantity: 20, category: 2, description: 'Modules' }
          ],
          job_start: '2025-02-05'
        }
      ]
    end

    before do
      job.update!(po_results: po_results)
    end

    context 'when job is completed' do
      it 'fetches PO PDFs from NetSuite' do
        expect(Netsuite::PurchaseOrder).to receive(:fetch_pdf_binary).with(12345).and_return(mock_pdf_binary)
        expect(Netsuite::PurchaseOrder).to receive(:fetch_pdf_binary).with(12346).and_return(mock_pdf_binary)

        # Mock service methods
        allow_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)
        allow_any_instance_of(PoGenerationService).to receive(:generate_location_summary_pdf).and_return("SUMMARY_PDF")
        allow(Lightreach::DirectPayMailer).to receive_message_chain(:regional_pos_created, :send_google)

        service.send_batch_email
      end

      it 'uploads POs to Lightreach when account_id is present' do
        expect_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)
          .with(hash_including(po_id: 12345, lightreach_account_id: 'LR-123'), mock_pdf_binary)
        expect_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)
          .with(hash_including(po_id: 12346, lightreach_account_id: 'LR-124'), mock_pdf_binary)
        allow_any_instance_of(PoGenerationService).to receive(:generate_location_summary_pdf).and_return("SUMMARY_PDF")

        allow(Lightreach::DirectPayMailer).to receive_message_chain(:regional_pos_created, :send_google)

        service.send_batch_email(test_mode: false)
      end

      it 'skips Lightreach upload in test mode' do
        expect_any_instance_of(PoGenerationService).not_to receive(:upload_po_to_lightreach)
        allow_any_instance_of(PoGenerationService).to receive(:generate_location_summary_pdf).and_return("SUMMARY_PDF")

        allow(Lightreach::DirectPayMailer).to receive_message_chain(:regional_pos_created, :send_google)

        service.send_batch_email(test_mode: true)
      end

      it 'groups POs by region and sends regional emails' do
        allow_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)
        allow_any_instance_of(PoGenerationService).to receive(:generate_location_summary_pdf).and_return("SUMMARY_PDF")

        # Should send 2 emails (one for Austin, one for Dallas)
        expect(Lightreach::DirectPayMailer).to receive(:regional_pos_created)
          .with(hash_including(region: 'Austin'))
          .and_return(double(send_google: true))

        expect(Lightreach::DirectPayMailer).to receive(:regional_pos_created)
          .with(hash_including(region: 'Dallas'))
          .and_return(double(send_google: true))

        service.send_batch_email
      end

      it 'generates regional summary PDFs' do
        allow_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)

        expect_any_instance_of(PoGenerationService).to receive(:generate_location_summary_pdf)
          .with(array_including(hash_including(location_name: 'Austin')), 'Austin')
          .and_return("AUSTIN_SUMMARY_PDF")

        expect_any_instance_of(PoGenerationService).to receive(:generate_location_summary_pdf)
          .with(array_including(hash_including(location_name: 'Dallas')), 'Dallas')
          .and_return("DALLAS_SUMMARY_PDF")

        allow(Lightreach::DirectPayMailer).to receive_message_chain(:regional_pos_created, :send_google)

        service.send_batch_email
      end
    end

    context 'when job is not completed' do
      before do
        job.update!(status: 'running')
      end

      it 'does not send emails' do
        expect(Lightreach::DirectPayMailer).not_to receive(:regional_pos_created)
        service.send_batch_email
      end
    end

    context 'when po_results is empty' do
      before do
        job.update!(po_results: [])
      end

      it 'does not send emails' do
        expect(Lightreach::DirectPayMailer).not_to receive(:regional_pos_created)
        service.send_batch_email
      end
    end

    context 'when an error occurs' do
      before do
        allow(Netsuite::PurchaseOrder).to receive(:fetch_pdf_binary).and_raise(StandardError, "NetSuite error")
      end

      it 'logs the error and re-raises' do
        expect(Rails.logger).to receive(:error).with(/Failed to send batch PO email/)
        expect { service.send_batch_email }.to raise_error(StandardError, "NetSuite error")
      end
    end
  end

  describe '#send_single_email' do
    let(:po_result) do
      {
        po_id: 12345,
        project_id: 'SF-001',
        project_name: 'Austin Project 1',
        location_name: 'Austin',
        lightreach_account_id: 'LR-123',
        po_items: [
          { part_number: 'PSR-B168', quantity: 10, category: 3, description: 'Racking' }
        ]
      }
    end

    it 'fetches PO PDF from NetSuite' do
      expect(Netsuite::PurchaseOrder).to receive(:fetch_pdf_binary).with(12345).and_return(mock_pdf_binary)

      allow_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)
      allow(Lightreach::DirectPayMailer).to receive_message_chain(:single_po_created, :send_google)

      service.send_single_email(po_result)
    end

    it 'uploads PO to Lightreach when account_id is present' do
      expect_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)
        .with(hash_including(po_id: 12345, lightreach_account_id: 'LR-123'), mock_pdf_binary)

      allow(Lightreach::DirectPayMailer).to receive_message_chain(:single_po_created, :send_google)

      service.send_single_email(po_result)
    end

    it 'does not upload to Lightreach when account_id is absent' do
      po_result_without_account = po_result.merge(lightreach_account_id: nil)

      expect_any_instance_of(PoGenerationService).not_to receive(:upload_po_to_lightreach)

      allow(Lightreach::DirectPayMailer).to receive_message_chain(:single_po_created, :send_google)

      service.send_single_email(po_result_without_account)
    end

    it 'sends email with mailer' do
      allow_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)

      expect(Lightreach::DirectPayMailer).to receive(:single_po_created)
        .with(hash_including(
          po_data: hash_including(po_id: 12345),
          pdf_binary: mock_pdf_binary,
          cc_email: nil
        ))
        .and_return(double(send_google: true))

      service.send_single_email(po_result)
    end

    it 'includes CC email when provided' do
      allow_any_instance_of(PoGenerationService).to receive(:upload_po_to_lightreach)

      expect(Lightreach::DirectPayMailer).to receive(:single_po_created)
        .with(hash_including(cc_email: 'test@example.com'))
        .and_return(double(send_google: true))

      service.send_single_email(po_result, cc_email: 'test@example.com')
    end

    context 'when an error occurs' do
      before do
        allow(Netsuite::PurchaseOrder).to receive(:fetch_pdf_binary).and_raise(StandardError, "NetSuite error")
      end

      it 'logs the error and re-raises' do
        expect(Rails.logger).to receive(:error).with(/Failed to send single PO email/)
        expect { service.send_single_email(po_result) }.to raise_error(StandardError, "NetSuite error")
      end
    end
  end
end
