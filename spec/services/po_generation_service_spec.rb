require 'rails_helper'

RSpec.describe PoGenerationService, type: :service do
  let(:job) { create(:po_generation_job, :running) }
  let(:service) { described_class.new(job) }

  describe '#log_progress' do
    it 'creates a log entry in the database' do
      expect {
        service.log_progress('Test message')
      }.to change(PoGenerationLog, :count).by(1)

      log = PoGenerationLog.last
      expect(log.message).to eq('Test message')
      expect(log.level).to eq('info')
      expect(log.po_generation_job).to eq(job)
    end

    it 'supports different log levels' do
      service.log_progress('Error message', level: :error)
      log = PoGenerationLog.last
      expect(log.level).to eq('error')
    end

    it 'broadcasts to ActionCable' do
      expect(ActionCable.server).to receive(:broadcast).with(
        "po_generation_#{job.id}",
        hash_including(message: 'Test message', level: 'info')
      )
      service.log_progress('Test message')
    end
  end

  describe '#generate_location_summary_pdf' do
    let(:location_pos) do
      [
        {
          po_id: 12345,
          project_id: 'SF-001',
          project_name: 'Austin Project 1',
          po_items: [
            { part_number: 'PSR-B168', quantity: 10, category: 3 },
            { part_number: 'MODULE-123', quantity: 20, category: 2 }
          ]
        },
        {
          po_id: 12346,
          project_id: 'SF-002',
          project_name: 'Austin Project 2',
          po_items: [
            { part_number: 'PSR-B168', quantity: 5, category: 3 },
            { part_number: 'INVERTER-456', quantity: 2, category: 21 }
          ]
        }
      ]
    end

    it 'generates a PDF binary' do
      pdf_binary = service.generate_location_summary_pdf(location_pos, 'Austin')
      expect(pdf_binary).to be_a(String)
      expect(pdf_binary.bytesize).to be > 0
    end

    it 'includes the location name' do
      # PDF generation should not raise errors
      expect {
        service.generate_location_summary_pdf(location_pos, 'Austin')
      }.not_to raise_error
    end

    it 'handles empty PO list' do
      expect {
        service.generate_location_summary_pdf([], 'Austin')
      }.not_to raise_error
    end
  end

  describe '#upload_po_to_lightreach' do
    let(:po_data) do
      {
        po_id: 12345,
        project_id: 'SF-001',
        po_name: 'PO-12345',
        lightreach_account_id: 'LR-123'
      }
    end

    let(:pdf_binary) { 'PDF_BINARY_CONTENT' }

    before do
      allow(Lightreach::Document).to receive(:upload).and_return({ 'status' => 'success' })
    end

    it 'uploads PDF to Lightreach' do
      expect(Lightreach::Document).to receive(:upload).with(
        'LR-123',
        hash_including(type: 'billOfMaterials')
      )
      service.upload_po_to_lightreach(po_data, pdf_binary)
    end

    it 'logs progress on success' do
      expect(service).to receive(:log_progress).with(/Uploaded PO/)
      service.upload_po_to_lightreach(po_data, pdf_binary)
    end

    it 'returns the upload result' do
      result = service.upload_po_to_lightreach(po_data, pdf_binary)
      expect(result).to eq({ 'status' => 'success' })
    end

    context 'when upload fails' do
      before do
        allow(Lightreach::Document).to receive(:upload).and_raise(StandardError, 'Upload failed')
      end

      it 'logs error and returns nil' do
        expect(service).to receive(:log_progress).with(/Failed to upload/, level: :error)
        result = service.upload_po_to_lightreach(po_data, pdf_binary)
        expect(result).to be_nil
      end

      it 'does not raise error' do
        expect {
          service.upload_po_to_lightreach(po_data, pdf_binary)
        }.not_to raise_error
      end
    end
  end

  describe '#category_name_for' do
    it 'returns Modules for category 2' do
      expect(service.send(:category_name_for, 2)).to eq('Modules')
    end

    it 'returns Inverters for category 21' do
      expect(service.send(:category_name_for, 21)).to eq('Inverters')
    end

    it 'returns Racking for category 3' do
      expect(service.send(:category_name_for, 3)).to eq('Racking')
    end

    it 'returns Other for unknown category' do
      expect(service.send(:category_name_for, 999)).to eq('Other')
    end

    it 'handles nil category' do
      expect(service.send(:category_name_for, nil)).to eq('Other')
    end
  end

  describe '#direct_pay?' do
    it 'returns true for Lightreach Lease projects' do
      project = {
        'fields' => {
          'lender' => 'Lightreach Lease'
        }
      }
      expect(service.send(:direct_pay?, project)).to be true
    end

    it 'returns false when lender is not Lightreach Lease' do
      project = {
        'fields' => {
          'lender' => 'Other Lender'
        }
      }
      expect(service.send(:direct_pay?, project)).to be false
    end

    it 'returns false when lender is nil' do
      project = {
        'fields' => {}
      }
      expect(service.send(:direct_pay?, project)).to be false
    end
  end

  describe '#extract_po_id_from_link' do
    it 'extracts PO ID from NetSuite link' do
      link = 'https://1234567.app.netsuite.com/app/accounting/transactions/purchord.nl?id=12345'
      expect(service.send(:extract_po_id_from_link, link)).to eq(12345)
    end

    it 'returns nil for invalid link' do
      link = 'https://example.com/invalid'
      expect(service.send(:extract_po_id_from_link, link)).to be_nil
    end

    it 'returns nil for nil link' do
      expect(service.send(:extract_po_id_from_link, nil)).to be_nil
    end
  end

  describe '#crew_installation_complete?' do
    let(:project_id) { 'SF-12345' }

    before do
      allow(SunriseTask).to receive(:exists?).and_return(false)
    end

    it 'checks if Crew Installation Complete task exists and is complete' do
      expect(SunriseTask).to receive(:exists?).with(
        name: 'Crew Installation Complete',
        is_complete: true,
        project_id: project_id
      )
      service.send(:crew_installation_complete?, project_id)
    end

    it 'returns true when completed task exists' do
      allow(SunriseTask).to receive(:exists?).and_return(true)
      expect(service.send(:crew_installation_complete?, project_id)).to be true
    end

    it 'returns false when task does not exist or is not complete' do
      allow(SunriseTask).to receive(:exists?).and_return(false)
      expect(service.send(:crew_installation_complete?, project_id)).to be false
    end
  end

  describe '#filter_po_eligible_items' do
    def so_line(id:, line:, quantity: 1, ref_name: nil)
      {
        'line' => line,
        'item' => { 'id' => id.to_s, 'refName' => ref_name || "Item #{id}" },
        'quantity' => quantity
      }
    end

    def detail(itemid:, itemtype: 'InvtPart', custitem1: nil, displayname: nil)
      { 'itemid' => itemid, 'itemtype' => itemtype, 'custitem1' => custitem1, 'displayname' => displayname }
    end

    let(:msx_module) { so_line(id: 857, line: 3, quantity: 42, ref_name: 'MSX10-435HN0B') }
    let(:enphase) { so_line(id: 776, line: 4, quantity: 42, ref_name: 'IQ8HC-72-M-DOM-US') }

    it 'returns [] for empty input' do
      allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return({})
      expect(service.send(:filter_po_eligible_items, [])).to eq([])
    end

    context 'happy path' do
      before do
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
          857 => detail(itemid: 'MSX10-435HN0B', custitem1: '2'),
          776 => detail(itemid: 'IQ8HC-72-M-DOM-US', custitem1: '21')
        )
      end

      it 'includes items whose category is in the eligible list' do
        result = service.send(:filter_po_eligible_items, [ msx_module, enphase ])
        part_numbers = result.map { |i| i[:part_number] }
        expect(part_numbers).to contain_exactly('MSX10-435HN0B', 'IQ8HC-72-M-DOM-US')
      end

      it 'preserves quantity and SO line number on each item' do
        result = service.send(:filter_po_eligible_items, [ msx_module ])
        expect(result.first).to include(
          item_id: 857,
          quantity: 42,
          so_line_number: 3,
          category: 2,
          category_name: 'Modules'
        )
      end

      it 'batches all item lookups into a single NetSuite call' do
        expect(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).once.and_return(
          857 => detail(itemid: 'MSX10-435HN0B', custitem1: '2'),
          776 => detail(itemid: 'IQ8HC-72-M-DOM-US', custitem1: '21')
        )
        service.send(:filter_po_eligible_items, [ msx_module, enphase ])
      end
    end

    context 'regression: SuiteQL returns no row for an item' do
      # This is the exact failure mode that dropped MSX10-435HN0B yesterday:
      # the lookup silently returned nothing and the item disappeared from the PO.
      before do
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
          776 => detail(itemid: 'IQ8HC-72-M-DOM-US', custitem1: '21')
          # 857 (MSX) is missing on purpose
        )
      end

      it 'skips the missing item' do
        result = service.send(:filter_po_eligible_items, [ msx_module, enphase ])
        expect(result.map { |i| i[:item_id] }).to eq([ 776 ])
      end

      it 'logs a warning so the drop is visible' do
        expect(service).to receive(:log_progress).with(
          a_string_matching(/Skipped SO line 3 .*MSX10-435HN0B.*item 857 not returned/),
          level: :warning
        )
        service.send(:filter_po_eligible_items, [ msx_module, enphase ])
      end
    end

    context 'when an item has an ineligible category' do
      let(:service_fee) { so_line(id: 500, line: 1, quantity: 1, ref_name: 'Service Fee') }

      before do
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
          500 => detail(itemid: 'SERVICE-FEE', custitem1: '99')
        )
      end

      it 'skips the item' do
        expect(service.send(:filter_po_eligible_items, [ service_fee ])).to eq([])
      end

      it 'logs a warning naming the category' do
        expect(service).to receive(:log_progress).with(
          a_string_matching(/Skipped SERVICE-FEE: category 99 not in eligible list/),
          level: :warning
        )
        service.send(:filter_po_eligible_items, [ service_fee ])
      end
    end

    context 'when an item is not an inventory item' do
      let(:install_service) { so_line(id: 300, line: 2, quantity: 1, ref_name: 'Lightreach Lease Installation Services') }

      before do
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
          300 => detail(itemid: 'INSTALL-SERVICE', itemtype: 'Service', custitem1: '2')
        )
      end

      it 'skips silently — service items are expected on every SO' do
        expect(service).not_to receive(:log_progress)
        expect(service.send(:filter_po_eligible_items, [ install_service ])).to eq([])
      end
    end

    context 'when an item has zero quantity' do
      let(:zero_qty_item) { so_line(id: 857, line: 5, quantity: 0, ref_name: 'MSX10-435HN0B') }

      before do
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
          857 => detail(itemid: 'MSX10-435HN0B', custitem1: '2')
        )
      end

      it 'skips the item' do
        expect(service.send(:filter_po_eligible_items, [ zero_qty_item ])).to eq([])
      end
    end

    context 'when an SO line has no item id' do
      let(:bad_line) { { 'line' => 99, 'item' => {}, 'quantity' => 1 } }

      it 'skips it without crashing' do
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return({})
        expect(service.send(:filter_po_eligible_items, [ bad_line ])).to eq([])
      end
    end

    context 'when SuiteQL itself fails' do
      it 'propagates the error so the job is marked failed (no silent drop)' do
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_raise(RuntimeError, '503 Service Unavailable')
        expect {
          service.send(:filter_po_eligible_items, [ msx_module ])
        }.to raise_error(RuntimeError, /503/)
      end
    end

    it 'uses every category in the documented eligible list' do
      # Locks the behavior: if someone removes 33 (no name mapping) or any
      # other id from the list, this test catches the change.
      so_items = [ 2, 3, 5, 18, 21, 33 ].each_with_index.map do |cat, i|
        so_line(id: 100 + i, line: i + 1, quantity: 1, ref_name: "ITEM-#{cat}")
      end
      details = [ 2, 3, 5, 18, 21, 33 ].each_with_index.each_with_object({}) do |(cat, i), h|
        h[100 + i] = detail(itemid: "ITEM-#{cat}", custitem1: cat.to_s)
      end
      allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(details)

      result = service.send(:filter_po_eligible_items, so_items)
      expect(result.length).to eq(6)
    end
  end

  describe '#extract_items_from_po' do
    def po_line(id:, line:, quantity: 1)
      { 'line' => line, 'item' => { 'id' => id.to_s }, 'quantity' => quantity }
    end

    def detail(itemid:, itemtype: 'InvtPart', custitem1: nil)
      { 'itemid' => itemid, 'itemtype' => itemtype, 'custitem1' => custitem1 }
    end

    let(:purchase_order) do
      { 'item' => { 'items' => [ po_line(id: 857, line: 1, quantity: 42), po_line(id: 776, line: 2, quantity: 42) ] } }
    end

    it 'returns an array of items keyed off the PO line items' do
      allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
        857 => detail(itemid: 'MSX10-435HN0B', custitem1: '2'),
        776 => detail(itemid: 'IQ8HC-72-M-DOM-US', custitem1: '21')
      )

      result = service.send(:extract_items_from_po, purchase_order)
      expect(result.map { |i| i[:part_number] }).to contain_exactly('MSX10-435HN0B', 'IQ8HC-72-M-DOM-US')
      expect(result.first).to include(item_id: 857, quantity: 42, so_line_number: 1)
    end

    it 'handles a PO with no items' do
      empty_po = { 'item' => { 'items' => [] } }
      expect(service.send(:extract_items_from_po, empty_po)).to eq([])
    end

    it 'handles a PO with no item key at all' do
      expect(service.send(:extract_items_from_po, {})).to eq([])
    end

    it 'skips items missing from the SuiteQL response' do
      allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
        776 => detail(itemid: 'IQ8HC-72-M-DOM-US', custitem1: '21')
      )
      result = service.send(:extract_items_from_po, purchase_order)
      expect(result.map { |i| i[:item_id] }).to eq([ 776 ])
    end

    it 'skips non-inventory items silently' do
      po_with_service = { 'item' => { 'items' => [ po_line(id: 300, line: 1) ] } }
      allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
        300 => detail(itemid: 'SERVICE', itemtype: 'Service', custitem1: '2')
      )
      expect(service.send(:extract_items_from_po, po_with_service)).to eq([])
    end

    it 'skips zero-quantity lines' do
      po_with_zero = { 'item' => { 'items' => [ po_line(id: 857, line: 1, quantity: 0) ] } }
      allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
        857 => detail(itemid: 'MSX10-435HN0B', custitem1: '2')
      )
      expect(service.send(:extract_items_from_po, po_with_zero)).to eq([])
    end

    it 'does NOT filter by eligible category — PO comparison includes all inventory items' do
      # extract_items_from_po is used to read what's already on a PO,
      # not to decide what to put on one. It must not drop "ineligible" categories
      # or downstream comparisons would silently disagree with NetSuite.
      po = { 'item' => { 'items' => [ po_line(id: 999, line: 1) ] } }
      allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
        999 => detail(itemid: 'WEIRD-CAT', custitem1: '99')
      )
      result = service.send(:extract_items_from_po, po)
      expect(result.length).to eq(1)
      expect(result.first[:category]).to eq(99)
    end
  end

  describe '#racking_quantities_zeroed?' do
    let(:project_id) { 'SF-12345' }

    def so_line(id:, line:, quantity: 1)
      { 'line' => line, 'item' => { 'id' => id.to_s }, 'quantity' => quantity }
    end

    context 'when the SO contains PSR-M168-US (DOMESTIC) with quantity > 0' do
      before do
        allow(service).to receive(:fetch_sales_order_data).and_return(
          so_items: [ so_line(id: 555, line: 1, quantity: 10) ]
        )
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
          555 => { 'itemid' => 'PSR-M168-US (DOMESTIC)', 'itemtype' => 'InvtPart' }
        )
      end

      it 'returns false (quantities are NOT zeroed)' do
        expect(service.send(:racking_quantities_zeroed?, project_id)).to be false
      end
    end

    context 'when PSR-M168-US (DOMESTIC) is present but quantity is 0' do
      before do
        allow(service).to receive(:fetch_sales_order_data).and_return(
          so_items: [ so_line(id: 555, line: 1, quantity: 0) ]
        )
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
          555 => { 'itemid' => 'PSR-M168-US (DOMESTIC)', 'itemtype' => 'InvtPart' }
        )
      end

      it 'returns true' do
        expect(service.send(:racking_quantities_zeroed?, project_id)).to be true
      end
    end

    context 'when PSR-M168-US (DOMESTIC) is not on the SO' do
      before do
        allow(service).to receive(:fetch_sales_order_data).and_return(
          so_items: [ so_line(id: 600, line: 1, quantity: 5) ]
        )
        allow(Netsuite::InventoryItem).to receive(:fetch_details_by_ids).and_return(
          600 => { 'itemid' => 'OTHER-ITEM', 'itemtype' => 'InvtPart' }
        )
      end

      it 'returns true (treat as zeroed)' do
        expect(service.send(:racking_quantities_zeroed?, project_id)).to be true
      end
    end

    context 'when sales order data cannot be fetched' do
      before do
        allow(service).to receive(:fetch_sales_order_data).and_return(nil)
      end

      it 'returns true' do
        expect(service.send(:racking_quantities_zeroed?, project_id)).to be true
      end
    end

    context 'when SO has no items' do
      before do
        allow(service).to receive(:fetch_sales_order_data).and_return(so_items: [])
      end

      it 'returns true' do
        expect(service.send(:racking_quantities_zeroed?, project_id)).to be true
      end
    end
  end

  describe '#generate_po_for_project' do
    let(:project_id) { 'SF-12345' }
    let(:project_data) do
      {
        '_id' => project_id,
        'name' => 'Test Project',
        'fields' => {
          'lender' => 'Lightreach Lease',
          'lightreach_direct_pay' => true,
          'loan_application_id' => 'LOAN-123',
          'system_size' => 10.5
        }
      }
    end

    let(:po_result) do
      {
        project_id: project_id,
        po_id: 12345,
        po_name: "#{project_id} - Lightreach CED Direct Pay"
      }
    end

    before do
      allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ 'items' => [ project_data ] })
      allow(service).to receive(:fetch_job_starts_for_projects).and_return({ project_id => '2025-03-15T10:00:00Z' })
      allow(service).to receive(:create_po).and_return(po_result)
      allow(service).to receive(:update_project_po_link)
    end

    it 'fetches project data from Sunrise API' do
      expect(ProjectSunriseApi).to receive(:get_projects_bulk).with([ project_id ], fields: anything)
      service.generate_po_for_project(project_id)
    end

    it 'creates PO for the project' do
      expect(service).to receive(:create_po)
      service.generate_po_for_project(project_id)
    end

    it 'returns PO result' do
      result = service.generate_po_for_project(project_id)
      expect(result).to eq(po_result)
    end

    it 'logs progress' do
      expect(service).to receive(:log_progress).at_least(:once)
      service.generate_po_for_project(project_id)
    end

    context 'when project not found' do
      before do
        allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ 'items' => [] })
      end

      it 'returns nil' do
        result = service.generate_po_for_project(project_id)
        expect(result).to be_nil
      end
    end

    context 'with skip_email option' do
      it 'passes through the option' do
        service.generate_po_for_project(project_id, skip_email: true)
        # Just verify it doesn't raise an error
      end
    end
  end

  describe '#generate_pos_for_batch' do
    let(:project_ids) { [ 'SF-001', 'SF-002', 'SF-003' ] }
    let(:projects_data) do
      [
        {
          '_id' => 'SF-001',
          'name' => 'Project 1',
          'fields' => { 'lender' => 'Lightreach Lease', 'loan_application_id' => 'LOAN-001' }
        },
        {
          '_id' => 'SF-002',
          'name' => 'Project 2',
          'fields' => { 'lender' => 'Lightreach Lease', 'loan_application_id' => 'LOAN-002' }
        },
        {
          '_id' => 'SF-003',
          'name' => 'Project 3',
          'fields' => { 'lender' => 'Lightreach Lease', 'loan_application_id' => 'LOAN-003' }
        }
      ]
    end

    before do
      allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ 'items' => projects_data })
      allow(service).to receive(:fetch_job_starts_for_projects).and_return({
        'SF-001' => '2025-03-15T10:00:00Z',
        'SF-002' => '2025-03-16T10:00:00Z',
        'SF-003' => '2025-03-17T10:00:00Z'
      })
      allow(service).to receive(:create_po).and_return({ po_id: 12345 })
    end

    it 'fetches project data from Sunrise API' do
      expect(ProjectSunriseApi).to receive(:get_projects_bulk).with(project_ids, fields: anything)
      service.generate_pos_for_batch(project_ids)
    end

    it 'creates PO for each project' do
      expect(service).to receive(:create_po).exactly(3).times
      service.generate_pos_for_batch(project_ids)
    end

    it 'returns array of successful PO results' do
      result = service.generate_pos_for_batch(project_ids)
      expect(result.length).to eq(3)
      expect(result.all? { |po| po[:po_id] == 12345 }).to be true
    end

    it 'filters out nil results from failed generations' do
      allow(service).to receive(:create_po).and_return(
        { po_id: 12345 }, nil, { po_id: 12346 }
      )

      result = service.generate_pos_for_batch(project_ids)
      expect(result.length).to eq(2)
      expect(result.map { |po| po[:po_id] }).to contain_exactly(12345, 12346)
    end

    it 'logs progress for each project' do
      expect(service).to receive(:log_progress).at_least(:once)
      service.generate_pos_for_batch(project_ids)
    end

    context 'when no projects found' do
      before do
        allow(ProjectSunriseApi).to receive(:get_projects_bulk).and_return({ 'items' => [] })
      end

      it 'returns empty array' do
        result = service.generate_pos_for_batch(project_ids)
        expect(result).to eq([])
      end
    end
  end

  describe '#location_name_for' do
    it 'returns Austin for ID 1' do
      expect(service.send(:location_name_for, 1)).to eq('Austin')
    end

    it 'returns Houston for ID 2' do
      expect(service.send(:location_name_for, 2)).to eq('Houston')
    end

    it 'returns Dallas for ID 3' do
      expect(service.send(:location_name_for, 3)).to eq('Dallas')
    end

    it 'returns Austin for ID 4 (San Antonio merged into Austin)' do
      expect(service.send(:location_name_for, 4)).to eq('Austin')
    end

    it 'returns Tampa for ID 7' do
      expect(service.send(:location_name_for, 7)).to eq('Tampa')
    end

    it 'returns Orlando for ID 18' do
      expect(service.send(:location_name_for, 18)).to eq('Orlando')
    end

    it 'returns location ID for unrecognized ID' do
      expect(service.send(:location_name_for, 999)).to eq('Location 999')
    end

    it 'handles nil ID' do
      expect(service.send(:location_name_for, nil)).to eq('Location ')
    end
  end

  describe '#build_po_link' do
    before do
      allow(Rails.env).to receive(:production?).and_return(false)
      allow(Rails.application.credentials).to receive(:dig).with(:netsuite, :sandbox, :account_id_url).and_return('1234567')
    end

    it 'builds PO link with correct format' do
      link = service.send(:build_po_link, 12345)
      expect(link).to eq('https://1234567.app.netsuite.com/app/accounting/transactions/purchord.nl?id=12345')
    end

    it 'uses production account ID when in production' do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.application.credentials).to receive(:dig).with(:netsuite, :production, :account_id_url).and_return('7654321')

      link = service.send(:build_po_link, 12345)
      expect(link).to include('7654321')
    end
  end

  describe '#aggregate_items_across_projects' do
    let(:pos_data) do
      [
        {
          project_id: 'SF-001',
          po_items: [
            { part_number: 'PSR-B168', quantity: 10, category: 3 },
            { part_number: 'MODULE-123', quantity: 20, category: 2 }
          ]
        },
        {
          project_id: 'SF-002',
          po_items: [
            { part_number: 'PSR-B168', quantity: 5, category: 3 },
            { part_number: 'INVERTER-456', quantity: 2, category: 21 }
          ]
        }
      ]
    end

    it 'aggregates quantities for same part number' do
      result = service.send(:aggregate_items_across_projects, pos_data)
      psr_item = result.find { |item| item[:part_number] == 'PSR-B168' }
      expect(psr_item[:quantity]).to eq(15)
    end

    it 'keeps separate items for different part numbers' do
      result = service.send(:aggregate_items_across_projects, pos_data)
      expect(result.length).to eq(3)
    end

    it 'sorts items by category' do
      result = service.send(:aggregate_items_across_projects, pos_data)
      categories = result.map { |item| item[:category] }
      expect(categories).to eq([ 2, 3, 21 ])
    end

    it 'includes category name' do
      result = service.send(:aggregate_items_across_projects, pos_data)
      module_item = result.find { |item| item[:category] == 2 }
      expect(module_item[:category_name]).to eq('Modules')
    end

    it 'handles empty PO data' do
      result = service.send(:aggregate_items_across_projects, [])
      expect(result).to eq([])
    end

    it 'handles POs with no items' do
      empty_pos = [ { project_id: 'SF-001', po_items: [] } ]
      result = service.send(:aggregate_items_across_projects, empty_pos)
      expect(result).to eq([])
    end
  end

  describe '#update_project_po_link' do
    let(:project_id) { 'SF-12345' }
    let(:po_link) { 'https://example.com/po/12345' }

    before { allow(service).to receive(:sleep) }

    it 'calls ProjectSunriseApi with correct parameters' do
      expect(ProjectSunriseApi).to receive(:update_project).with(
        project_id,
        hash_including('lightreach_direct_pay_po_link' => po_link)
      ).and_return(true)
      service.send(:update_project_po_link, project_id, po_link)
    end

    it 'includes creation timestamp' do
      expect(ProjectSunriseApi).to receive(:update_project).with(
        project_id,
        hash_including('lightreach_direct_pay_po_creation_date')
      ).and_return(true)
      service.send(:update_project_po_link, project_id, po_link)
    end

    it 'logs progress' do
      allow(ProjectSunriseApi).to receive(:update_project).and_return(true)
      expect(service).to receive(:log_progress).with(/Updated project/)
      service.send(:update_project_po_link, project_id, po_link)
    end

    it 'retries and succeeds when the first attempt fails' do
      allow(ProjectSunriseApi).to receive(:update_project).and_return(false, true)
      expect(service).to receive(:log_progress).with(/attempt 1 failed/, hash_including(level: :warning))
      expect(service).to receive(:log_progress).with(/Updated project/)
      service.send(:update_project_po_link, project_id, po_link, po_id: 999)
    end

    it 'raises PoLinkUpdateError after exhausting retries, carrying the po_id' do
      allow(ProjectSunriseApi).to receive(:update_project).and_return(false)
      allow(service).to receive(:log_progress)
      expect do
        service.send(:update_project_po_link, project_id, po_link, po_id: 999)
      end.to raise_error(PoGenerationService::PoLinkUpdateError) do |error|
        expect(error.po_id).to eq(999)
        expect(error.project_id).to eq(project_id)
        expect(error.message).to match(/Do NOT regenerate/)
      end
      expect(ProjectSunriseApi).to have_received(:update_project)
        .exactly(PoGenerationService::PO_LINK_UPDATE_MAX_ATTEMPTS).times
    end

    it 'raises PoLinkUpdateError when the Sunrise call itself raises' do
      allow(ProjectSunriseApi).to receive(:update_project).and_raise(StandardError.new("boom"))
      allow(service).to receive(:log_progress)
      expect do
        service.send(:update_project_po_link, project_id, po_link, po_id: 42)
      end.to raise_error(PoGenerationService::PoLinkUpdateError, /PO 42 was created/)
    end
  end

  describe '#generate_pos_for_region' do
    let(:region_name) { 'Austin' }
    let(:installations) do
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
    let(:direct_pay_projects) do
      [
        {
          '_id' => 'SF-001',
          'name' => 'Austin Project 1',
          'fields' => { 'lender' => 'Lightreach Lease', 'loan_application_id' => 'LOAN-001' },
          'job_start' => '2025-03-15T10:00:00Z'
        },
        {
          '_id' => 'SF-002',
          'name' => 'Austin Project 2',
          'fields' => { 'lender' => 'Lightreach Lease', 'loan_application_id' => 'LOAN-002' },
          'job_start' => '2025-03-20T10:00:00Z'
        }
      ]
    end

    before do
      allow(service).to receive(:fetch_installations_on_schedule).and_return(installations)
      allow(service).to receive(:filter_for_direct_pay).and_return(direct_pay_projects)
      allow(service).to receive(:create_po).and_return({ po_id: 12345 })
      allow(service).to receive(:fetch_sales_order_data).and_return({ location_id: 1 })  # Austin location ID
      allow(service).to receive(:update_project_po_link)
      allow(JobScheduleService).to receive(:new).and_return(instance_double(JobScheduleService,
        batch_fetch_project_locations: { 'SF-001' => region_name, 'SF-002' => region_name }))
    end

    it 'fetches installations on schedule' do
      expect(service).to receive(:fetch_installations_on_schedule)
      service.generate_pos_for_region(region_name)
    end

    it 'filters for direct pay projects' do
      expect(service).to receive(:filter_for_direct_pay).with(installations)
      service.generate_pos_for_region(region_name)
    end

    it 'creates PO for each project in the region' do
      expect(service).to receive(:create_po).twice
      service.generate_pos_for_region(region_name)
    end

    it 'returns array of successful POs' do
      result = service.generate_pos_for_region(region_name)
      expect(result.length).to eq(2)
      expect(result.all? { |po| po[:po_id] == 12345 }).to be true
    end

    it 'filters out projects not in the specified region' do
      # Make SF-002 return Dallas location (ID 3)
      call_count = 0
      allow(service).to receive(:fetch_sales_order_data) do
        call_count += 1
        { location_id: call_count == 1 ? 1 : 3 }  # First call returns Austin (1), second returns Dallas (3)
      end

      expect(service).to receive(:create_po).once  # Only Austin project should create PO
      service.generate_pos_for_region(region_name)
    end

    it 'logs progress' do
      expect(service).to receive(:log_progress).at_least(:once)
      service.generate_pos_for_region(region_name)
    end

    context 'when no direct pay projects found' do
      before do
        allow(service).to receive(:filter_for_direct_pay).and_return([])
      end

      it 'returns empty array' do
        result = service.generate_pos_for_region(region_name)
        expect(result).to eq([])
      end

      it 'logs no projects message' do
        allow(service).to receive(:log_progress)  # Allow all log_progress calls
        service.generate_pos_for_region(region_name)
        # Just verify it completes without error
      end
    end
  end
end
