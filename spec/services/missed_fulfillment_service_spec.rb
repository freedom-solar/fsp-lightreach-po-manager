require 'rails_helper'

RSpec.describe MissedFulfillmentService do
  let(:service) { described_class.new }
  let(:netsuite_client) { instance_double(Netsuite::Client) }

  # SO headers: one non-storage SO (governed by installation date) and one
  # storage SO (governed by electrical date).
  let(:headers) do
    [
      {
        'so_id' => 1, 'project_number' => '119001', 'customer' => 'Smith',
        'status_code' => 'B', 'install_date' => '1/1/2026', 'electrical_date' => '1/5/2026'
      },
      {
        'so_id' => 2, 'project_number' => '119002', 'customer' => 'Jones',
        'status_code' => 'D', 'install_date' => '1/1/2026', 'electrical_date' => '1/5/2026'
      }
    ]
  end

  let(:line_meta) do
    [
      { 'so_id' => 1, 'has_storage' => 0, 'location_id' => 1 },
      { 'so_id' => 2, 'has_storage' => 1, 'location_id' => 2 }
    ]
  end

  let(:locations) do
    [ { 'id' => 1, 'name' => 'Austin' }, { 'id' => 2, 'name' => 'Houston' } ]
  end

  before do
    allow(Netsuite::Client).to receive(:new).and_return(netsuite_client)
    # Order of suiteql calls: headers, line_meta, locations.
    allow(netsuite_client).to receive(:suiteql).and_return(
      { 'items' => headers, 'hasMore' => false },
      { 'items' => line_meta, 'hasMore' => false },
      { 'items' => locations, 'hasMore' => false }
    )
  end

  describe '#report' do
    it 'returns sales orders past their governing scheduled date' do
      result = service.report
      expect(result[:count]).to eq(2)
      expect(result[:rows].map { |r| r[:project_number] }).to contain_exactly('119001', '119002')
    end

    it 'governs a non-storage SO by the installation date' do
      row = service.report[:rows].find { |r| r[:project_number] == '119001' }
      expect(row[:has_storage]).to be false
      expect(row[:governing_basis]).to eq('installation')
      expect(row[:location]).to eq('Austin')
      expect(row[:status_label]).to eq('Pending Fulfillment')
    end

    it 'governs a storage SO by the electrical date' do
      row = service.report[:rows].find { |r| r[:project_number] == '119002' }
      expect(row[:has_storage]).to be true
      expect(row[:governing_basis]).to eq('electrical')
      expect(row[:location]).to eq('Houston')
    end

    it 'sorts most overdue first' do
      # 119001 governed by install 1/1 (older) is more overdue than 119002 by electrical 1/5
      result = service.report
      expect(result[:rows].first[:project_number]).to eq('119001')
      expect(result[:rows].first[:days_overdue]).to be > result[:rows].last[:days_overdue]
    end
  end

  describe '#report date handling' do
    it 'excludes SOs whose governing date is in the future' do
      future = [
        {
          'so_id' => 3, 'project_number' => '119003', 'customer' => 'Future',
          'status_code' => 'B', 'install_date' => "1/1/#{Date.current.year + 2}", 'electrical_date' => nil
        }
      ]
      allow(netsuite_client).to receive(:suiteql).and_return(
        { 'items' => future, 'hasMore' => false },
        { 'items' => [ { 'so_id' => 3, 'has_storage' => 0, 'location_id' => 1 } ], 'hasMore' => false },
        { 'items' => locations, 'hasMore' => false }
      )

      expect(service.report[:rows]).to be_empty
    end

    it 'falls back to the installation date for storage SOs with no electrical date' do
      storage_no_elec = [
        {
          'so_id' => 5, 'project_number' => '119005', 'customer' => 'StoreNoElec',
          'status_code' => 'B', 'install_date' => '1/1/2026', 'electrical_date' => nil
        }
      ]
      allow(netsuite_client).to receive(:suiteql).and_return(
        { 'items' => storage_no_elec, 'hasMore' => false },
        { 'items' => [ { 'so_id' => 5, 'has_storage' => 1, 'location_id' => 1 } ], 'hasMore' => false },
        { 'items' => locations, 'hasMore' => false }
      )

      row = service.report[:rows].first
      expect(row[:has_storage]).to be true
      expect(row[:governing_basis]).to eq('installation')
      expect(row[:project_number]).to eq('119005')
    end

    it 'excludes SOs with no governing date (not yet scheduled)' do
      undated = [
        {
          'so_id' => 4, 'project_number' => '119004', 'customer' => 'NoDate',
          'status_code' => 'B', 'install_date' => nil, 'electrical_date' => nil
        }
      ]
      allow(netsuite_client).to receive(:suiteql).and_return(
        { 'items' => undated, 'hasMore' => false },
        { 'items' => [ { 'so_id' => 4, 'has_storage' => 0, 'location_id' => 1 } ], 'hasMore' => false },
        { 'items' => locations, 'hasMore' => false }
      )

      expect(service.report[:rows]).to be_empty
    end
  end
end
