require 'rails_helper'

RSpec.describe ProcurementDashboardService do
  let(:service) { described_class.new }
  let(:netsuite_client) { instance_double(Netsuite::Client) }

  # Two lines on PO-100 (Commercial / Austin) and one line on PO-200
  # (Residential / Houston).
  let(:lines) do
    [
      {
        'po_id' => 100, 'po_number' => 'PO-100', 'vendor' => 'Devlin',
        'status_code' => 'D', 'ns_class' => 'Commercial', 'location' => 'Austin',
        'project' => 'C100 Foo', 'quantity' => 2, 'quantity_received' => 1,
        'quantity_billed' => 1, 'rate' => 100
      },
      {
        'po_id' => 100, 'po_number' => 'PO-100', 'vendor' => 'Devlin',
        'status_code' => 'D', 'ns_class' => 'Commercial', 'location' => 'Austin',
        'project' => 'C100 Foo', 'quantity' => 1, 'quantity_received' => 0,
        'quantity_billed' => 0, 'rate' => 50
      },
      {
        'po_id' => 200, 'po_number' => 'PO-200', 'vendor' => 'Acme',
        'status_code' => 'F', 'ns_class' => 'Residential', 'location' => 'Houston',
        'project' => 'S200 Bar', 'quantity' => 1, 'quantity_received' => 1,
        'quantity_billed' => 0, 'rate' => 200
      }
    ]
  end

  before do
    allow(Netsuite::Client).to receive(:new).and_return(netsuite_client)
    allow(netsuite_client).to receive(:suiteql)
      .and_return({ 'items' => lines, 'hasMore' => false })
  end

  describe '#dashboard' do
    subject(:result) { service.dashboard }

    it 'aggregates lines into one row per PO + class + location' do
      expect(result[:count]).to eq(2)
      expect(result[:rows].map { |r| r[:po_number] }).to contain_exactly('PO-100', 'PO-200')
    end

    it 'sums quantities and amounts within a PO group' do
      po100 = result[:rows].find { |r| r[:po_number] == 'PO-100' }

      expect(po100[:ordered_qty]).to eq(3)
      expect(po100[:received_qty]).to eq(1)
      expect(po100[:billed_qty]).to eq(1)
      # (2 * 100) + (1 * 50)
      expect(po100[:amount]).to eq(250.0)
      # unbilled: (2-1)*100 + (1-0)*50
      expect(po100[:unbilled_amount]).to eq(150.0)
    end

    it 'flags pending receipt and pending bill independently' do
      po100 = result[:rows].find { |r| r[:po_number] == 'PO-100' }
      po200 = result[:rows].find { |r| r[:po_number] == 'PO-200' }

      expect(po100[:pending_receipt]).to be true
      expect(po100[:pending_bill]).to be true

      # PO-200 is fully received (1 of 1) but not billed
      expect(po200[:pending_receipt]).to be false
      expect(po200[:pending_bill]).to be true
    end

    it 'maps status codes to human labels' do
      po100 = result[:rows].find { |r| r[:po_number] == 'PO-100' }
      expect(po100[:status_label]).to eq('Partially Received')
    end

    it 'collects distinct project names per group' do
      po100 = result[:rows].find { |r| r[:po_number] == 'PO-100' }
      expect(po100[:projects]).to eq([ 'C100 Foo' ])
    end

    it 'totals the unbilled amount across all rows' do
      expect(result[:total_unbilled_amount]).to eq(350.0)
    end

    it 'sorts rows by class, location, vendor, then PO number' do
      expect(result[:rows].first[:po_number]).to eq('PO-100') # Commercial before Residential
    end

    it 'includes a generated_at timestamp' do
      expect(result[:generated_at]).to be_present
    end

    it 'constrains the SuiteQL query to open Contract Labor PO lines' do
      service.dashboard
      expect(netsuite_client).to have_received(:suiteql)
        .with(hash_including(query: a_string_including('tl.item = 325')))
        .at_least(:once)
    end
  end

  describe '#dashboard with missing/blank fields' do
    let(:lines) do
      [
        {
          'po_id' => 300, 'po_number' => 'PO-300', 'vendor' => nil,
          'status_code' => 'B', 'ns_class' => nil, 'location' => nil,
          'project' => nil, 'quantity' => 1, 'quantity_received' => nil,
          'quantity_billed' => nil, 'rate' => nil
        }
      ]
    end

    it 'applies sensible defaults' do
      row = service.dashboard[:rows].first

      expect(row[:vendor]).to eq('Unknown Vendor')
      expect(row[:ns_class]).to eq('Unclassified')
      expect(row[:location]).to eq('No Location')
      expect(row[:amount]).to eq(0.0)
      expect(row[:projects]).to eq([])
      expect(row[:pending_receipt]).to be true
    end
  end

  describe '#dashboard pagination' do
    it 'fetches additional pages while hasMore is true' do
      page1 = { 'items' => [ lines[0] ], 'hasMore' => true }
      page2 = { 'items' => [ lines[2] ], 'hasMore' => false }
      allow(netsuite_client).to receive(:suiteql).and_return(page1, page2)

      result = service.dashboard

      expect(netsuite_client).to have_received(:suiteql).twice
      expect(result[:rows].map { |r| r[:po_number] }).to contain_exactly('PO-100', 'PO-200')
    end
  end
end
