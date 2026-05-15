require 'rails_helper'

RSpec.describe AddRackingQuantitiesToSoWorker, type: :worker do
  let(:worker) { described_class.new }
  let(:project_id) { 'SF-12345' }
  let(:sales_order_id) { 98765 }

  describe '#perform' do
    let(:mock_bom_file) do
      double('BOM File', path: Rails.root.join('spec/fixtures/files/sample_bom.pdf'))
    end

    let(:mock_bom_data) { { 'file' => mock_bom_file } }

    let(:mock_sales_order) do
      {
        'id' => sales_order_id,
        'item' => {
          'items' => [
            {
              'line' => 1,
              'item' => { 'id' => '100' },
              'quantity' => 5,
              'quantityFulfilled' => 0
            }
          ]
        }
      }
    end

    before do
      # Mock external API calls
      allow(ProjectSunriseApi).to receive(:get_file).and_return(mock_bom_data)
      allow(Netsuite::SalesOrder).to receive(:find_external).and_return({ 'id' => sales_order_id })
      allow(Netsuite::SalesOrder).to receive(:find).and_return(mock_sales_order)
      allow(Netsuite::SalesOrder).to receive(:update).and_return({ 'status' => 'success' })
    end

    context 'when BOM file is not found' do
      before do
        allow(ProjectSunriseApi).to receive(:get_file).and_return({ 'file' => nil })
      end

      it 'logs error and returns nil' do
        expect(worker).to receive(:log_error).with(project_id, 'No BOM file found')
        worker.perform(project_id)
      end
    end

    context 'when no Pegasus racking items found in BOM' do
      before do
        allow(worker).to receive(:parse_racking_items_from_bom).and_return([])
        allow(worker).to receive(:log_progress).and_call_original
      end

      it 'logs warning and continues processing other BOM items' do
        # Should log warning about no racking (not error/return early)
        expect(worker).to receive(:log_progress).with(
          "No Pegasus racking items found in BOM (battery-only job?)", level: :warning
        )
        # Should continue to completion (not return early)
        expect(worker).to receive(:log_progress).with(
          "Successfully updated racking quantities for project #{project_id}", level: :success
        )
        worker.perform(project_id)
      end
    end

    context 'when sales order ID is not found' do
      before do
        allow(Netsuite::SalesOrder).to receive(:find_external).and_return({})
        allow(worker).to receive(:parse_racking_items_from_bom).and_return([
          { part_number: 'PSR-B168', quantity: 10, description: 'Pegasus Rail' }
        ])
      end

      it 'logs error and returns nil' do
        expect(worker).to receive(:log_error).with(project_id, 'Could not find NetSuite Sales Order ID')
        worker.perform(project_id)
      end
    end

    context 'when sales order cannot be fetched from NetSuite' do
      before do
        allow(Netsuite::SalesOrder).to receive(:find).and_return(nil)
        allow(worker).to receive(:parse_racking_items_from_bom).and_return([
          { part_number: 'PSR-B168', quantity: 10, description: 'Pegasus Rail' }
        ])
      end

      it 'logs error and returns nil' do
        expect(worker).to receive(:log_error).with(project_id, 'Could not fetch Sales Order from NetSuite')
        worker.perform(project_id)
      end
    end

    context 'when worker executes successfully' do
      before do
        allow(worker).to receive(:parse_racking_items_from_bom).and_return([
          { part_number: 'PSR-B168', quantity: 10, description: 'Pegasus Rail' }
        ])
        allow(worker).to receive(:parse_items_from_bom).and_return([])
        allow(worker).to receive(:update_racking_quantities)
        allow(worker).to receive(:add_envoy_items_to_so)
        allow(worker).to receive(:handle_combiner_wifi_on_so)
      end

      it 'updates racking quantities' do
        expect(worker).to receive(:update_racking_quantities)
        worker.perform(project_id)
      end

      it 'processes Enphase Envoy items' do
        expect(worker).to receive(:parse_items_from_bom).with(
          mock_bom_file,
          hash_including(search_string: 'ENV-IQ-AM1-240', item_name: 'Enphase Envoy')
        )
        worker.perform(project_id)
      end

      it 'handles Combiner-WIFI-5 items' do
        expect(worker).to receive(:handle_combiner_wifi_on_so)
        worker.perform(project_id)
      end
    end

    context 'when an error occurs' do
      before do
        allow(ProjectSunriseApi).to receive(:get_file).and_raise(StandardError, 'API Error')
      end

      it 'logs the error and re-raises' do
        expect(worker).to receive(:log_error).with(project_id, /Error: API Error/)
        expect { worker.perform(project_id) }.to raise_error(StandardError, 'API Error')
      end
    end
  end

  describe '#parse_racking_items_from_bom' do
    let(:mock_pdf_text) do
      <<~PDF
        PSR-B168 Pegasus Rail - Black 168" 16 EA
        PIF-RBDT Pegasus InstaFlash - Black - Dovetail T-bolt 49 EA
        PSR-MCB Pegasus Mid Clamp - Black 32 EA
        Some other item without Pegasus 10 EA
      PDF
    end

    let(:mock_bom_file) { double('BOM File', path: '/tmp/test.pdf') }
    let(:mock_reader) { double('PDF Reader') }
    let(:mock_page) { double('PDF Page', text: mock_pdf_text) }

    before do
      allow(PDF::Reader).to receive(:new).and_return(mock_reader)
      allow(mock_reader).to receive(:pages).and_return([ mock_page ])
    end

    it 'extracts Pegasus racking items with correct quantities' do
      result = worker.send(:parse_racking_items_from_bom, mock_bom_file)

      expect(result).to be_an(Array)
      expect(result.length).to eq(3)

      expect(result[0]).to include(
        part_number: 'PSR-B168',
        quantity: 16
      )

      expect(result[1]).to include(
        part_number: 'PIF-RBDT',
        quantity: 49
      )

      expect(result[2]).to include(
        part_number: 'PSR-MCB',
        quantity: 32
      )
    end

    it 'ignores non-Pegasus items' do
      result = worker.send(:parse_racking_items_from_bom, mock_bom_file)
      expect(result.map { |i| i[:description] }).to all(include('Pegasus'))
    end

    context 'when PDF parsing fails' do
      before do
        allow(PDF::Reader).to receive(:new).and_raise(StandardError, 'PDF Error')
      end

      it 'returns empty array' do
        result = worker.send(:parse_racking_items_from_bom, mock_bom_file)
        expect(result).to eq([])
      end
    end
  end

  describe '#parse_items_from_bom' do
    let(:mock_pdf_text) do
      <<~PDF
        ENV-IQ-AM1-240 Enphase Envoy 1 EA
        X-IQ-AM1-240-5-HDK HomeRun Data Kit 2 EA
      PDF
    end

    let(:mock_bom_file) { double('BOM File', path: '/tmp/test.pdf') }
    let(:mock_reader) { double('PDF Reader') }
    let(:mock_page) { double('PDF Page', text: mock_pdf_text) }

    before do
      allow(PDF::Reader).to receive(:new).and_return(mock_reader)
      allow(mock_reader).to receive(:pages).and_return([ mock_page ])
    end

    it 'finds items matching search string' do
      result = worker.send(:parse_items_from_bom, mock_bom_file,
                          search_string: 'ENV-IQ-AM1-240',
                          item_name: 'Enphase Envoy')

      expect(result.length).to eq(1)
      expect(result[0]).to include(
        description: 'Enphase Envoy',
        quantity: 1
      )
    end

    it 'returns empty array when search string not found' do
      result = worker.send(:parse_items_from_bom, mock_bom_file,
                          search_string: 'NOT-FOUND',
                          item_name: 'Non-existent Item')

      expect(result).to eq([])
    end
  end

  describe '#item_fulfilled?' do
    it 'returns true when quantityFulfilled is positive' do
      item = { 'quantityFulfilled' => 5 }
      expect(worker.send(:item_fulfilled?, item)).to be true
    end

    it 'returns false when quantityFulfilled is 0' do
      item = { 'quantityFulfilled' => 0 }
      expect(worker.send(:item_fulfilled?, item)).to be false
    end

    it 'returns false when quantityFulfilled is nil' do
      item = {}
      expect(worker.send(:item_fulfilled?, item)).to be false
    end
  end

  describe '#extract_class_and_location' do
    let(:items) do
      [
        { 'class' => { 'id' => '10' }, 'location' => { 'id' => '20' } },
        { 'class' => { 'id' => '11' }, 'location' => { 'id' => '21' } }
      ]
    end

    it 'extracts class and location from first item' do
      result = worker.send(:extract_class_and_location, items)
      expect(result).to eq({
        'class' => { 'id' => '10' },
        'location' => { 'id' => '20' }
      })
    end

    it 'returns empty hash when items is empty' do
      result = worker.send(:extract_class_and_location, [])
      expect(result).to eq({})
    end
  end

  describe '#find_matching_so_item' do
    let(:so_items) do
      [
        {
          'line' => 1,
          'item' => { 'id' => '100', 'refName' => 'PSR-M168-US (DOMESTIC)' },
          'quantity' => 10
        },
        {
          'line' => 2,
          'item' => { 'id' => '101', 'refName' => 'PSR-MCZ-US (DOMESTIC)' },
          'quantity' => 20
        }
      ]
    end

    let(:item_details_cache) do
      {
        '100' => { 'itemId' => 'PSR-M168-US (DOMESTIC)', 'name' => 'Pegasus Rail' },
        '101' => { 'itemId' => 'PSR-MCZ-US (DOMESTIC)', 'name' => 'Pegasus Mid Clamp' }
      }
    end

    context 'exact match' do
      it 'finds item by exact part number match' do
        result = worker.send(:find_matching_so_item, so_items, 'PSR-M168-US (DOMESTIC)', item_details_cache)
        expect(result['line']).to eq(1)
      end
    end

    context 'special mappings' do
      it 'maps PSR-B168 to PSR-M168-US (DOMESTIC)' do
        result = worker.send(:find_matching_so_item, so_items, 'PSR-B168', item_details_cache)
        expect(result['line']).to eq(1)
      end

      it 'maps PSR-B84 to PSR-M168-US (DOMESTIC)' do
        result = worker.send(:find_matching_so_item, so_items, 'PSR-B84', item_details_cache)
        expect(result['line']).to eq(1)
      end

      it 'maps PSR-MCB to PSR-MCZ-US (DOMESTIC)' do
        result = worker.send(:find_matching_so_item, so_items, 'PSR-MCB', item_details_cache)
        expect(result['line']).to eq(2)
      end

      it 'maps PSR-HEC to PSR-MCZ-US (DOMESTIC)' do
        result = worker.send(:find_matching_so_item, so_items, 'PSR-HEC', item_details_cache)
        expect(result['line']).to eq(2)
      end
    end

    it 'returns nil when no match found' do
      result = worker.send(:find_matching_so_item, so_items, 'UNKNOWN-PART', item_details_cache)
      expect(result).to be_nil
    end
  end

  describe '#add_envoy_items_to_so' do
    let(:envoy_items) { [ { quantity: 2, description: 'Enphase Envoy' } ] }
    let(:sales_order) do
      {
        'item' => {
          'items' => [
            { 'line' => 1, 'item' => { 'id' => '100' }, 'class' => { 'id' => '10' }, 'location' => { 'id' => '20' } }
          ]
        }
      }
    end

    before do
      allow(Netsuite::SalesOrder).to receive(:find).and_return(sales_order)
      allow(Netsuite::SalesOrder).to receive(:update).and_return({ 'status' => 'success' })
    end

    it 'adds both Enphase Envoy and ENP CT-200-SPLIT items' do
      expect(Netsuite::SalesOrder).to receive(:update) do |so_id, body|
        items = body.dig(:item, :items)

        # Should add Envoy
        envoy_item = items.find { |i| i.dig(:item, :id) == described_class::ENPHASE_ENVOY_ITEM_ID }
        expect(envoy_item).to be_present
        expect(envoy_item[:quantity]).to eq(2)

        # Should add CT-200-SPLIT
        ct_item = items.find { |i| i.dig(:item, :id) == described_class::ENP_CT_200_SPLIT_ITEM_ID }
        expect(ct_item).to be_present
        expect(ct_item[:quantity]).to eq(2)

        { 'status' => 'success' }
      end

      worker.send(:add_envoy_items_to_so, project_id, sales_order_id, envoy_items)
    end

    it 'skips fulfilled Envoy items' do
      sales_order['item']['items'] << {
        'line' => 2,
        'item' => { 'id' => described_class::ENPHASE_ENVOY_ITEM_ID },
        'quantity' => 1,
        'quantityFulfilled' => 1
      }

      allow(Netsuite::SalesOrder).to receive(:find).and_return(sales_order)

      expect(Netsuite::SalesOrder).not_to receive(:update)
      worker.send(:add_envoy_items_to_so, project_id, sales_order_id, envoy_items)
    end
  end

  describe '#handle_combiner_wifi_on_so' do
    let(:sales_order) do
      {
        'item' => {
          'items' => [
            { 'line' => 1, 'item' => { 'id' => '100' }, 'class' => { 'id' => '10' }, 'location' => { 'id' => '20' } }
          ]
        }
      }
    end

    before do
      allow(Netsuite::SalesOrder).to receive(:find).and_return(sales_order)
      allow(Netsuite::SalesOrder).to receive(:update).and_return({ 'status' => 'success' })
    end

    context 'when HDK items are present' do
      let(:hdk_items) { [ { quantity: 1, description: 'HomeRun Data Kit' } ] }

      it 'adds Combiner-WIFI-5 item' do
        expect(Netsuite::SalesOrder).to receive(:update) do |so_id, body|
          items = body.dig(:item, :items)
          combiner_item = items.find { |i| i.dig(:item, :id) == described_class::COMBINER_WIFI_5_ITEM_ID }
          expect(combiner_item).to be_present
          expect(combiner_item[:quantity]).to eq(1)

          { 'status' => 'success' }
        end

        worker.send(:handle_combiner_wifi_on_so, project_id, sales_order_id, hdk_items)
      end
    end

    context 'when HDK items are absent and Combiner exists' do
      let(:hdk_items) { [] }

      before do
        sales_order['item']['items'] << {
          'line' => 2,
          'item' => { 'id' => described_class::COMBINER_WIFI_5_ITEM_ID },
          'quantity' => 1,
          'quantityFulfilled' => 0
        }
      end

      it 'removes Combiner-WIFI-5 item' do
        expect(Netsuite::SalesOrder).to receive(:update) do |so_id, body, options|
          items = body.dig(:item, :items)
          combiner_item = items.find { |i| i.dig(:item, :id) == described_class::COMBINER_WIFI_5_ITEM_ID }
          expect(combiner_item).to be_nil
          expect(options[:replace_item]).to be true

          { 'status' => 'success' }
        end

        worker.send(:handle_combiner_wifi_on_so, project_id, sales_order_id, hdk_items)
      end
    end
  end
end
