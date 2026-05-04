require 'rails_helper'

RSpec.describe JobScheduleService do
  let(:service) { described_class.new }
  let(:start_time) { Time.now.beginning_of_day }
  let(:end_time) { (Time.now + 1.week).end_of_week }

  describe '#fetch_direct_pay_on_schedule' do
    let(:installation_jobs) do
      [
        {
          'node' => {
            'ProjectSunriseID' => 'SF-001',
            'Start' => '2025-03-15T10:00:00Z'
          }
        },
        {
          'node' => {
            'ProjectSunriseID' => 'SF-002',
            'Start' => '2025-03-20T10:00:00Z'
          }
        }
      ]
    end

    let(:projects_response) do
      {
        'items' => [
          {
            '_id' => 'SF-001',
            'name' => 'Austin Project 1',
            'fields' => {
              'lender' => 'Lightreach Lease',
              'system_size' => 10.5,
              'loan_application_id' => 'LOAN-001'
            }
          },
          {
            '_id' => 'SF-002',
            'name' => 'Houston Project 1',
            'fields' => {
              'lender' => 'Lightreach Lease',
              'system_size' => 12.0,
              'loan_application_id' => 'LOAN-002'
            }
          }
        ]
      }
    end

    before do
      allow(SkeduloApi).to receive(:find_jobs).with('Installation', start_time: start_time, end_time: end_time).and_return(installation_jobs)
      allow(SkeduloApi).to receive(:find_jobs).with('Tesla Powerwall', start_time: start_time, end_time: end_time).and_return([])
      allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return(projects_response)
    end

    context 'without region filter' do
      it 'returns all direct pay projects' do
        result = service.fetch_direct_pay_on_schedule
        expect(result.length).to eq(2)
        expect(result.map { |p| p['_id'] }).to contain_exactly('SF-001', 'SF-002')
      end

      it 'adds job start dates to projects' do
        result = service.fetch_direct_pay_on_schedule
        project = result.find { |p| p['_id'] == 'SF-001' }
        expect(project['job_start']).to eq('2025-03-15T10:00:00Z')
      end
    end

    context 'with region filter' do
      before do
        allow(service).to receive(:batch_fetch_project_locations).and_return({
          'SF-001' => 'Austin',
          'SF-002' => 'Houston'
        })
      end

      it 'returns only projects in specified region' do
        result = service.fetch_direct_pay_on_schedule(region: 'Austin')
        expect(result.length).to eq(1)
        expect(result.first['_id']).to eq('SF-001')
      end

      it 'handles nil locations' do
        allow(service).to receive(:batch_fetch_project_locations).and_return({
          'SF-001' => nil,
          'SF-002' => 'Houston'
        })

        result = service.fetch_direct_pay_on_schedule(region: 'Austin')
        expect(result).to be_empty
      end
    end
  end

  describe '#location_name_for' do
    it 'returns Austin for location ID 1' do
      expect(service.send(:location_name_for, 1)).to eq('Austin')
    end

    it 'returns Houston for location ID 2' do
      expect(service.send(:location_name_for, 2)).to eq('Houston')
    end

    it 'returns Dallas for location ID 3' do
      expect(service.send(:location_name_for, 3)).to eq('Dallas')
    end

    it 'returns Tampa for location ID 7' do
      expect(service.send(:location_name_for, 7)).to eq('Tampa')
    end

    it 'returns default string for unknown location' do
      expect(service.send(:location_name_for, 999)).to eq('Location 999')
    end

    it 'handles string location IDs' do
      expect(service.send(:location_name_for, '1')).to eq('Austin')
    end

    it 'handles nil location ID' do
      expect(service.send(:location_name_for, nil)).to eq('Location ')
    end
  end

  describe '#fetch_sales_order_id' do
    let(:project_id) { 'SF-12345' }
    let(:sales_order) { { 'id' => 98765 } }

    before do
      allow(Netsuite::SalesOrder).to receive(:find_external).and_return(sales_order)
    end

    it 'fetches sales order by external ID' do
      expect(Netsuite::SalesOrder).to receive(:find_external).with('sales_order_SF-12345')
      service.send(:fetch_sales_order_id, project_id)
    end

    it 'returns sales order ID' do
      result = service.send(:fetch_sales_order_id, project_id)
      expect(result).to eq(98765)
    end

    context 'when sales order not found' do
      before do
        allow(Netsuite::SalesOrder).to receive(:find_external).and_raise(StandardError, 'Not found')
      end

      it 'returns nil' do
        result = service.send(:fetch_sales_order_id, project_id)
        expect(result).to be_nil
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).at_least(:once)
        service.send(:fetch_sales_order_id, project_id)
      end
    end
  end

  describe '#fetch_sales_order_data' do
    let(:project_id) { 'SF-12345' }
    let(:sales_order_id) { 98765 }
    let(:sales_order) do
      {
        'entity' => { 'id' => 123 },
        'job' => { 'id' => 456 },
        'location' => { 'id' => 1 },
        'shipAddress' => '123 Main St',
        'item' => {
          'items' => [
            { 'item' => { 'internalId' => '1' }, 'quantity' => 10 }
          ]
        }
      }
    end

    before do
      allow(service).to receive(:fetch_sales_order_id).and_return(sales_order_id)
      allow(Netsuite::SalesOrder).to receive(:find).and_return(sales_order)
    end

    it 'returns sales order data' do
      result = service.send(:fetch_sales_order_data, project_id)

      expect(result[:sales_order_id]).to eq(sales_order_id)
      expect(result[:customer_id]).to eq(123)
      expect(result[:internal_project_id]).to eq(456)
      expect(result[:location_id]).to eq(1)
      expect(result[:ship_to_address]).to eq('123 Main St')
      expect(result[:so_items].length).to eq(1)
    end

    context 'when sales order ID not found' do
      before do
        allow(service).to receive(:fetch_sales_order_id).and_return(nil)
      end

      it 'returns nil' do
        result = service.send(:fetch_sales_order_data, project_id)
        expect(result).to be_nil
      end
    end

    context 'when sales order not found' do
      before do
        allow(Netsuite::SalesOrder).to receive(:find).and_return(nil)
      end

      it 'returns nil' do
        result = service.send(:fetch_sales_order_data, project_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#batch_fetch_project_locations' do
    let(:project_ids) { [ 'SF-001', 'SF-002' ] }
    let(:suiteql_result) do
      {
        'items' => [
          { 'externalid' => 'sales_order_SF-001', 'location' => 1 },
          { 'externalid' => 'sales_order_SF-002', 'location' => 2 }
        ]
      }
    end

    let(:netsuite_client) { instance_double(Netsuite::Client) }

    before do
      allow(Netsuite::Client).to receive(:new).and_return(netsuite_client)
      allow(netsuite_client).to receive(:suiteql).and_return(suiteql_result)
    end

    it 'returns location map' do
      result = service.send(:batch_fetch_project_locations, project_ids)
      expect(result['SF-001']).to eq('Austin')
      expect(result['SF-002']).to eq('Houston')
    end

    it 'handles empty project IDs' do
      result = service.send(:batch_fetch_project_locations, [])
      expect(result).to eq({})
    end

    it 'sets nil for projects without sales orders' do
      allow(netsuite_client).to receive(:suiteql).and_return({ 'items' => [] })

      result = service.send(:batch_fetch_project_locations, project_ids)
      expect(result['SF-001']).to be_nil
      expect(result['SF-002']).to be_nil
    end

    context 'when NetSuite query fails' do
      before do
        allow(netsuite_client).to receive(:suiteql).and_raise(StandardError, 'API Error')
      end

      it 'returns nil for all projects' do
        result = service.send(:batch_fetch_project_locations, project_ids)
        expect(result['SF-001']).to be_nil
        expect(result['SF-002']).to be_nil
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).at_least(:once)
        service.send(:batch_fetch_project_locations, project_ids)
      end
    end
  end

  describe '#filter_for_direct_pay' do
    let(:jobs) do
      [
        {
          'node' => {
            'ProjectSunriseID' => 'SF-001',
            'Start' => '2025-03-15T10:00:00Z'
          }
        },
        {
          'node' => {
            'ProjectSunriseID' => 'SF-002',
            'Start' => '2025-03-20T10:00:00Z'
          }
        },
        {
          'node' => {
            'ProjectSunriseID' => 'SF-002',
            'Start' => '2025-03-18T10:00:00Z'
          }
        }
      ]
    end

    let(:projects_response) do
      {
        'items' => [
          {
            '_id' => 'SF-001',
            'name' => 'Project 1',
            'fields' => {
              'lender' => 'Lightreach Lease',
              'system_size' => 10.5
            }
          },
          {
            '_id' => 'SF-002',
            'name' => 'Project 2',
            'fields' => {
              'lender' => 'Other Lender',
              'system_size' => 12.0
            }
          }
        ]
      }
    end

    before do
      allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return(projects_response)
    end

    it 'filters for Lightreach Lease projects only' do
      result = service.send(:filter_for_direct_pay, jobs)
      expect(result.length).to eq(1)
      expect(result.first['_id']).to eq('SF-001')
    end

    it 'adds job start date to projects' do
      result = service.send(:filter_for_direct_pay, jobs)
      expect(result.first['job_start']).to eq('2025-03-15T10:00:00Z')
    end

    it 'uses earliest start date for duplicate projects' do
      projects_response['items'][1]['fields']['lender'] = 'Lightreach Lease'
      result = service.send(:filter_for_direct_pay, jobs)

      project = result.find { |p| p['_id'] == 'SF-002' }
      expect(project['job_start']).to eq('2025-03-18T10:00:00Z')
    end

    it 'handles jobs without project IDs' do
      jobs_with_nil = jobs + [ { 'node' => { 'Start' => '2025-03-15T10:00:00Z' } } ]
      expect { service.send(:filter_for_direct_pay, jobs_with_nil) }.not_to raise_error
    end

    it 'returns empty array when no project IDs' do
      result = service.send(:filter_for_direct_pay, [])
      expect(result).to eq([])
    end
  end

  describe '#fetch_installations_on_schedule' do
    let(:installation_jobs) { [ { 'node' => { 'ProjectSunriseID' => 'SF-001' } } ] }
    let(:powerwall_jobs) { [ { 'node' => { 'ProjectSunriseID' => 'SF-002' } } ] }

    before do
      allow(SkeduloApi).to receive(:find_jobs).with('Installation', start_time: start_time, end_time: end_time).and_return(installation_jobs)
      allow(SkeduloApi).to receive(:find_jobs).with('Tesla Powerwall', start_time: start_time, end_time: end_time).and_return(powerwall_jobs)
    end

    it 'fetches both Installation and Tesla Powerwall jobs' do
      expect(SkeduloApi).to receive(:find_jobs).with('Installation', start_time: start_time, end_time: end_time)
      expect(SkeduloApi).to receive(:find_jobs).with('Tesla Powerwall', start_time: start_time, end_time: end_time)

      service.send(:fetch_installations_on_schedule)
    end

    it 'combines both job types' do
      result = service.send(:fetch_installations_on_schedule)
      expect(result.length).to eq(2)
    end
  end
end
