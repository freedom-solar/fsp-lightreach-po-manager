require 'rails_helper'

RSpec.describe InventoryDashboardService do
  let(:service) { described_class.new }
  let(:netsuite_client) { instance_double(Netsuite::Client) }

  # Project 100: panel ordered 10, received 6, fulfilled (SO) 2.
  #   -> not_received 4, received_not_allocated 4.
  let(:po_lines) do
    [
      {
        'po_id' => 1, 'po_number' => 'PO-1', 'item_id' => 50, 'item_name' => 'Panel A',
        'project_number' => '100', 'project_name' => '100 - Smith', 'location' => 'Houston',
        'quantity' => 10, 'quantity_received' => 6
      }
    ]
  end

  let(:so_lines) do
    [
      { 'ext' => 'sales_order_100', 'item_id' => 50, 'fulfilled' => 2 }
    ]
  end

  before do
    allow(Netsuite::Client).to receive(:new).and_return(netsuite_client)
    # First SuiteQL call = PO lines; second = SO fulfilled lines.
    allow(netsuite_client).to receive(:suiteql).and_return(
      { 'items' => po_lines, 'hasMore' => false },
      { 'items' => so_lines, 'hasMore' => false }
    )
    allow(SkeduloApi).to receive(:find_jobs).and_return([])
  end

  describe '#dashboard' do
    it 'computes not-received and received-not-allocated per project + item' do
      row = service.dashboard[:rows].first

      expect(row[:project]).to eq('100 - Smith')
      expect(row[:item]).to eq('Panel A')
      expect(row[:ordered_qty]).to eq(10)
      expect(row[:received_qty]).to eq(6)
      expect(row[:not_received_qty]).to eq(4)
      expect(row[:received_not_allocated_qty]).to eq(4)
    end

    it 'only includes rows with a receiving or allocation gap' do
      # Fully received and fully allocated -> no gap -> excluded.
      allow(netsuite_client).to receive(:suiteql).and_return(
        { 'items' => [ po_lines.first.merge('quantity_received' => 10) ], 'hasMore' => false },
        { 'items' => [ { 'ext' => 'sales_order_100', 'item_id' => 50, 'fulfilled' => 10 } ], 'hasMore' => false }
      )

      expect(service.dashboard[:rows]).to be_empty
    end

    it 'is not late when the project has no schedule' do
      row = service.dashboard[:rows].first
      expect(row[:urgency]).to be_nil
      expect(row[:late]).to be false
    end
  end

  describe '#dashboard with a schedule' do
    def install_job(project_number, start)
      { 'node' => { 'ProjectSunriseID' => project_number, 'Start' => start, 'Region' => { 'Name' => 'Houston' } } }
    end

    it 'flags overdue installs with unready items as late' do
      allow(SkeduloApi).to receive(:find_jobs)
        .with('Installation', any_args).and_return([ install_job('100', 3.days.ago.iso8601) ])
      allow(SkeduloApi).to receive(:find_jobs).with('Tesla Powerwall', any_args).and_return([])

      result = service.dashboard
      row = result[:rows].first
      expect(row[:urgency]).to eq('overdue')
      expect(row[:late]).to be true
      expect(row[:region]).to eq('Houston')
      expect(result[:late_count]).to eq(1)
    end

    it 'flags installs within the at-risk window' do
      allow(SkeduloApi).to receive(:find_jobs)
        .with('Installation', any_args).and_return([ install_job('100', 3.days.from_now.iso8601) ])
      allow(SkeduloApi).to receive(:find_jobs).with('Tesla Powerwall', any_args).and_return([])

      expect(service.dashboard[:rows].first[:urgency]).to eq('at_risk')
    end

    it 'ignores installs beyond the at-risk window' do
      allow(SkeduloApi).to receive(:find_jobs)
        .with('Installation', any_args).and_return([ install_job('100', 30.days.from_now.iso8601) ])
      allow(SkeduloApi).to receive(:find_jobs).with('Tesla Powerwall', any_args).and_return([])

      expect(service.dashboard[:rows].first[:urgency]).to be_nil
    end
  end

  describe '#dashboard project number parsing' do
    it 'derives the project number from the entity display name leading token' do
      line = po_lines.first.merge('project_name' => '118811 118811 - Iris Montero')
      allow(netsuite_client).to receive(:suiteql).and_return(
        { 'items' => [ line ], 'hasMore' => false },
        { 'items' => [ { 'ext' => 'sales_order_118811', 'item_id' => 50, 'fulfilled' => 3 } ], 'hasMore' => false }
      )

      row = service.dashboard[:rows].first
      expect(row[:project_number]).to eq('118811')
      # received 6 - SO-fulfilled 3 = 3, proving the SO matched via the parsed number
      expect(row[:received_not_allocated_qty]).to eq(3)
    end
  end

  describe '#dashboard surfaces SuiteQL errors' do
    it 'raises when NetSuite returns an error body instead of items' do
      allow(netsuite_client).to receive(:suiteql)
        .and_return({ 'type' => 'Bad Request', 'status' => 400 })

      expect { service.dashboard }.to raise_error(/NetSuite SuiteQL error/)
    end
  end

  describe '#dashboard when Skedulo fails' do
    it 'still returns NetSuite rows without schedule data' do
      allow(SkeduloApi).to receive(:find_jobs).and_raise(StandardError, 'Skedulo down')

      row = service.dashboard[:rows].first
      expect(row[:not_received_qty]).to eq(4)
      expect(row[:urgency]).to be_nil
    end
  end
end
