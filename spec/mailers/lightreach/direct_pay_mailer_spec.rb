require 'rails_helper'

RSpec.describe Lightreach::DirectPayMailer, type: :mailer do
  let(:mock_pdf_binary) { "PDF_BINARY_CONTENT" }

  describe '#regional_pos_created' do
    let(:region) { 'Austin' }
    let(:created_pos) do
      [
        {
          po_id: 12345,
          project_id: 'SF-001',
          project_name: 'Austin Project 1',
          location_name: 'Austin',
          po_items: [
            { part_number: 'PSR-B168', quantity: 10, category: 3 }
          ],
          job_start: '2025-02-01T10:00:00Z'
        },
        {
          po_id: 12346,
          project_id: 'SF-002',
          project_name: 'Austin Project 2',
          location_name: 'Austin',
          po_items: [
            { part_number: 'MODULE-123', quantity: 20, category: 2 }
          ],
          job_start: '2025-02-05T10:00:00Z'
        }
      ]
    end

    let(:po_pdfs) do
      [
        { po_id: 12345, project_id: 'SF-001', pdf_binary: mock_pdf_binary },
        { po_id: 12346, project_id: 'SF-002', pdf_binary: mock_pdf_binary }
      ]
    end

    let(:summary_pdf) { "SUMMARY_PDF_CONTENT" }

    before do
      # Mock DistributionList
      allow(DistributionList).to receive(:warehouse).and_return([ 'warehouse@example.com' ])
      allow(DistributionList).to receive(:regional_rom).and_return([ 'rom@example.com' ])
    end

    context 'in production mode' do
      let(:mail) do
        described_class.regional_pos_created(
          region: region,
          created_pos: created_pos,
          po_pdfs: po_pdfs,
          summary_pdf: summary_pdf,
          test_mode: false
        )
      end

      it 'renders the subject' do
        expect(mail.subject).to eq('Lightreach Direct Pay - Austin - 2 Purchase Orders Created')
      end

      it 'sends to correct recipients' do
        expected_recipients = [
          'dkimbriel@gofreedompower.com',
          'colby.clem@greentechrenewables.com',
          'jcarroll@gofreedompower.com',
          'dfisk@freedomsolarpower.com',
          'chad@freedomsolarpower.com',
          'warehouse@example.com',
          'rom@example.com',
          'Sydni.landreneau@greentechrenewables.com',
          'alex.juarez@greentechrenewables.com'
        ]
        expect(mail.to).to match_array(expected_recipients)
      end

      it 'sends from correct address' do
        expect(mail.from).to eq([ 'project_sunrise@gofreedompower.com' ])
      end

      it 'attaches regional summary PDF' do
        summary_attachment = mail.attachments.find { |a| a.filename == 'Lightreach_Direct_Pay_Austin_Summary.pdf' }
        expect(summary_attachment).to be_present
        expect(summary_attachment.content_type).to include('application/pdf')
        expect(summary_attachment.body.raw_source).to eq(summary_pdf)
      end

      it 'attaches individual PO PDFs' do
        po_attachment_1 = mail.attachments.find { |a| a.filename == 'PO_12345_SF-001.pdf' }
        expect(po_attachment_1).to be_present
        expect(po_attachment_1.body.raw_source).to eq(mock_pdf_binary)

        po_attachment_2 = mail.attachments.find { |a| a.filename == 'PO_12346_SF-002.pdf' }
        expect(po_attachment_2).to be_present
      end

      it 'has correct total attachments count' do
        # 1 summary PDF + 2 individual PO PDFs
        expect(mail.attachments.count).to eq(3)
      end

      it 'includes project details in email body' do
        expect(mail.body.encoded).to include('Austin Project 1')
        expect(mail.body.encoded).to include('Austin Project 2')
        expect(mail.body.encoded).to include('SF-001')
        expect(mail.body.encoded).to include('SF-002')
      end
    end

    context 'in test mode' do
      let(:mail) do
        described_class.regional_pos_created(
          region: region,
          created_pos: created_pos,
          po_pdfs: po_pdfs,
          summary_pdf: summary_pdf,
          test_mode: true
        )
      end

      it 'sends only to test email' do
        expect(mail.to).to eq([ 'dkimbriel@gofreedompower.com' ])
      end

      it 'includes [TEST] in subject' do
        expect(mail.subject).to eq('[TEST] Lightreach Direct Pay - Austin - 2 Purchase Orders Created')
      end
    end

    context 'for Tampa region' do
      let(:region) { 'Tampa' }
      let(:created_pos) do
        [
          {
            po_id: 12345,
            project_id: 'SF-001',
            project_name: 'Tampa Project 1',
            location_name: 'Tampa',
            po_items: [],
            job_start: '2025-02-01T10:00:00Z'
          }
        ]
      end
      let(:po_pdfs) { [ { po_id: 12345, project_id: 'SF-001', pdf_binary: mock_pdf_binary } ] }

      let(:mail) do
        described_class.regional_pos_created(
          region: region,
          created_pos: created_pos,
          po_pdfs: po_pdfs,
          summary_pdf: summary_pdf,
          test_mode: false
        )
      end

      it 'includes Tampa-specific contacts' do
        expect(mail.to).to include('hunter.david@greentechrenewables.com')
        expect(mail.to).to include('troy.walter@greentechrenewables.com')
      end
    end

    context 'for Orlando region' do
      let(:region) { 'Orlando' }
      let(:created_pos) do
        [
          {
            po_id: 12345,
            project_id: 'SF-001',
            project_name: 'Orlando Project 1',
            location_name: 'Orlando',
            po_items: [],
            job_start: '2025-02-01T10:00:00Z'
          }
        ]
      end
      let(:po_pdfs) { [ { po_id: 12345, project_id: 'SF-001', pdf_binary: mock_pdf_binary } ] }

      let(:mail) do
        described_class.regional_pos_created(
          region: region,
          created_pos: created_pos,
          po_pdfs: po_pdfs,
          summary_pdf: summary_pdf,
          test_mode: false
        )
      end

      it 'includes Orlando-specific contacts' do
        expect(mail.to).to include('David.Principato@greentechrenewables.com')
        expect(mail.to).to include('jordan.swanson@greentechrenewables.com')
      end
    end

    context 'when regional_rom returns nil' do
      before do
        allow(DistributionList).to receive(:warehouse).and_return([ 'warehouse@example.com' ])
        allow(DistributionList).to receive(:regional_rom).and_return(nil)
      end

      let(:mail) do
        described_class.regional_pos_created(
          region: 'Austin',
          created_pos: created_pos,
          po_pdfs: po_pdfs,
          summary_pdf: summary_pdf,
          test_mode: false
        )
      end

      it 'sends email without error' do
        expect { mail.deliver_now }.not_to raise_error
      end

      it 'does not include nil in recipients' do
        expect(mail.to).not_to include(nil)
      end
    end

    context 'with region name containing spaces' do
      let(:region) { 'San Antonio' }
      let(:created_pos) do
        [
          {
            po_id: 12345,
            project_id: 'SF-001',
            project_name: 'San Antonio Project 1',
            location_name: 'San Antonio',
            po_items: [],
            job_start: '2025-02-01T10:00:00Z'
          }
        ]
      end
      let(:po_pdfs) { [ { po_id: 12345, project_id: 'SF-001', pdf_binary: mock_pdf_binary } ] }

      let(:mail) do
        described_class.regional_pos_created(
          region: region,
          created_pos: created_pos,
          po_pdfs: po_pdfs,
          summary_pdf: summary_pdf,
          test_mode: false
        )
      end

      it 'replaces spaces with underscores in summary filename' do
        summary_attachment = mail.attachments.find { |a| a.filename == 'Lightreach_Direct_Pay_San_Antonio_Summary.pdf' }
        expect(summary_attachment).to be_present
      end
    end
  end

  describe '#single_po_created' do
    let(:po_data) do
      {
        po_id: 12345,
        project_id: 'SF-001',
        project_name: 'Austin Project 1',
        location_name: 'Austin',
        po_items: [
          { part_number: 'PSR-B168', quantity: 10, category: 3, description: 'Racking' }
        ]
      }
    end

    before do
      allow(DistributionList).to receive(:warehouse).and_return([ 'warehouse@example.com' ])
      allow(DistributionList).to receive(:regional_rom).and_return([ 'rom@example.com' ])
    end

    context 'without CC' do
      let(:mail) do
        described_class.single_po_created(
          po_data: po_data,
          pdf_binary: mock_pdf_binary,
          cc_email: nil
        )
      end

      it 'renders the subject' do
        expect(mail.subject).to eq('Lightreach Direct Pay PO Created - Project SF-001')
      end

      it 'sends to regional recipients' do
        expect(mail.to).to include('dkimbriel@gofreedompower.com')
        expect(mail.to).to include('colby.clem@greentechrenewables.com')
        expect(mail.to).to include('warehouse@example.com')
      end

      it 'does not have CC' do
        expect(mail.cc).to be_nil
      end

      it 'attaches PO PDF' do
        attachment = mail.attachments.find { |a| a.filename == 'PO_12345_SF-001.pdf' }
        expect(attachment).to be_present
        expect(attachment.body.raw_source).to eq(mock_pdf_binary)
      end
    end

    context 'with CC email' do
      let(:mail) do
        described_class.single_po_created(
          po_data: po_data,
          pdf_binary: mock_pdf_binary,
          cc_email: 'cc@example.com'
        )
      end

      it 'includes CC email' do
        expect(mail.cc).to eq([ 'cc@example.com' ])
      end
    end
  end
end
