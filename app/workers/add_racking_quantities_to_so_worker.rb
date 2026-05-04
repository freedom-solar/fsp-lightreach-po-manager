require 'pdf-reader'

class AddRackingQuantitiesToSoWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'po_generation', retry: 3

  # NetSuite item ID for Tesla Mid-Circuit Interrupter Gen2
  TESLA_MCI_GEN2_ITEM_ID = '939'
  # NetSuite item ID for Enphase Envoy
  ENPHASE_ENVOY_ITEM_ID = '941'
  # NetSuite item ID for ENP CT-200-SPLIT (required with Enphase Envoy)
  ENP_CT_200_SPLIT_ITEM_ID = '949'
  # NetSuite item ID for Combiner-WIFI-5
  COMBINER_WIFI_5_ITEM_ID = '734'
  # NetSuite item ID for PF-DW75 (Pegasus non-standard racking)
  PF_DW75_ITEM_ID = '948'
  # NetSuite item ID for PIF2-BDT (Pegasus non-standard racking)
  PIF2_BDT_ITEM_ID = '947'
  # PF-SF70 ITEM ID (Pegasus non-standard racking)
  PF_SF70_ITEM_ID = '956'
  # NetSuite item ID for Tesla 200A CT
  TESLA_200A_CT_ITEM_ID = '953'
  # NetSuite item ID for SUNMODO TOPTILE-7-B
  SUNMODO_TOPTILE_7_B_ITEM_ID = '954'

  # BOM items to parse and add to SO (standard flow)
  BOM_ITEM_CONFIGS = [
    { search_string: 'TESLA MID-CIRCUIT INTERRUPTER GEN2', item_id: TESLA_MCI_GEN2_ITEM_ID,
      item_name: 'Tesla MCI Gen2' },
    { search_string: 'PF-DW75', item_id: PF_DW75_ITEM_ID, item_name: 'PF-DW75' },
    { search_string: 'PIF2-BDT', item_id: PIF2_BDT_ITEM_ID, item_name: 'PIF2-BDT' },
    { search_string: '2033376-', item_id: TESLA_200A_CT_ITEM_ID, item_name: 'Tesla 200A CT' },
    { search_string: 'K10461-107-BK', item_id: SUNMODO_TOPTILE_7_B_ITEM_ID, item_name: 'SUNMODO TOPTILE-7-B' },
    { search_string: 'PF-SF70', item_id: PF_SF70_ITEM_ID, item_name: 'PF-SF70' }
  ].freeze

  def perform(project_id, job_id: nil, skip_status_check: false)
    @job_id = job_id
    log_progress("Processing project #{project_id} for racking quantities update")

    # Get BOM file from Sunrise
    bom_data = fetch_bom_file(project_id)
    return log_error(project_id, 'No BOM file found') unless bom_data['file']

    # Extract Pegasus racking items from BOM
    racking_items = parse_racking_items_from_bom(bom_data['file'])
    return log_error(project_id, 'No Pegasus racking items found in BOM') if racking_items.empty?

    log_progress("Found #{racking_items.size} Pegasus racking items in BOM")
    racking_items.each { |item| log_progress("  #{item[:part_number]}: #{item[:quantity]} EA") }

    # Get NetSuite Sales Order ID from HubSpot Deal
    sales_order_id = fetch_sales_order_id(project_id)
    return log_error(project_id, 'Could not find NetSuite Sales Order ID') unless sales_order_id

    log_progress("Found NetSuite Sales Order ID: #{sales_order_id}")

    # Fetch Sales Order from NetSuite
    sales_order = Netsuite::SalesOrder.find(sales_order_id)
    return log_error(project_id, 'Could not fetch Sales Order from NetSuite') unless sales_order

    # NOTE: We check individual line item fulfillment (quantityFulfilled) instead of SO-level status
    # This allows updating unfulfilled items even when other parts of the SO have been fulfilled

    # Update racking quantities on Sales Order (skips fulfilled items)
    update_racking_quantities(project_id, sales_order_id, sales_order, racking_items)

    # Parse and add Enphase Envoy items (special case: adds 2 items)
    envoy_items = parse_items_from_bom(bom_data['file'], search_string: 'ENV-IQ-AM1-240',
                                                         item_name: 'Enphase Envoy')
    add_envoy_items_to_so(project_id, sales_order_id, envoy_items) if envoy_items.any?

    # Handle Combiner-WIFI-5 (special case: adds/removes based on HDK presence)
    hdk_items = parse_items_from_bom(bom_data['file'], search_string: 'X-IQ-AM1-240-5-HDK',
                                                       item_name: 'X-IQ-AM1-240-5-HDK')
    handle_combiner_wifi_on_so(project_id, sales_order_id, hdk_items)

    # Parse and add standard BOM items
    BOM_ITEM_CONFIGS.each do |config|
      parse_and_add_item(bom_data['file'], project_id, sales_order_id, **config)
    end

    log_progress("Successfully updated racking quantities for project #{project_id}", level: :success)
  rescue StandardError => e
    log_error(project_id, "Error: #{e.message}\n#{e.backtrace.join("\n")}")
    raise
  end

  private

  # Broadcast log message via ActionCable (if job_id is provided) and to console
  def log_progress(message, level: :info)
    puts message

    return unless @job_id

    timestamp = Time.current.strftime("%H:%M:%S")
    log_entry = {
      timestamp: timestamp,
      level: level.to_s,
      message: message,
      job_id: @job_id
    }

    # Save to database
    job = PoGenerationJob.find_by(id: @job_id)
    if job
      PoGenerationLog.create!(
        po_generation_job: job,
        level: level.to_s,
        message: message
      )

      # Broadcast to ActionCable
      ActionCable.server.broadcast(
        "po_generation_#{@job_id}",
        log_entry
      )
    end
  rescue StandardError => e
    puts "Warning: Failed to log progress: #{e.message}"
  end

  def fetch_bom_file(project_id)
    ProjectSunriseApi.get_file(project_id, 'BOM')
  end

  def parse_racking_items_from_bom(bom_file)
    racking_items = []

    # Read PDF and extract text
    reader = PDF::Reader.new(bom_file.path)
    text = reader.pages.map(&:text).join("\n")

    # Parse each line looking for Pegasus items
    text.each_line do |line|
      # Look for lines containing "Pegasus" in the description
      next unless line.include?('Pegasus')

      # Extract part number and quantity
      # Format: "PSR-B168 Pegasus Rail - Black 168" 16 EA"
      # or: "PIF-RBDT Pegasus InstaFlash - Black - Dovetail T-bolt 49 EA"

      # Match pattern: Part# followed by description containing "Pegasus", then quantity and unit
      next unless line =~ /(P[SI][RFOW]-[A-Z0-9-]+)\s+.*Pegasus.*?\s+(\d+)\s+EA/i

      part_number = ::Regexp.last_match(1)
      quantity = ::Regexp.last_match(2).to_i

      racking_items << {
        part_number: part_number,
        quantity: quantity,
        description: line.strip
      }
    end

    racking_items
  rescue StandardError => e
    puts "Error parsing BOM PDF: #{e.message}"
    []
  end

  def parse_and_add_item(bom_file, project_id, sales_order_id, search_string:, item_id:, item_name:)
    items = parse_items_from_bom(bom_file, search_string: search_string, item_name: item_name)
    add_item_to_so(project_id, sales_order_id, items, item_id: item_id, item_name: item_name) if items.any?
  end

  def parse_items_from_bom(bom_file, search_string:, item_name:)
    items = []

    reader = PDF::Reader.new(bom_file.path)
    text = reader.pages.map(&:text).join("\n")

    text.each_line do |line|
      next unless line.include?(search_string)
      next unless line =~ /(\d+)\s+EA/i

      quantity = ::Regexp.last_match(1).to_i

      items << {
        description: item_name,
        quantity: quantity
      }
    end

    if items.any?
      log_progress("Found #{items.size} #{item_name} item(s) in BOM")
      items.each { |item| log_progress("  #{item_name}: #{item[:quantity]} EA") }
    end

    items
  rescue StandardError => e
    puts "Error parsing BOM PDF for #{item_name} items: #{e.message}"
    []
  end

  def add_item_to_so(project_id, sales_order_id, bom_items, item_id:, item_name:)
    return if bom_items.empty?

    total_quantity = bom_items.sum { |item| item[:quantity] }

    log_progress("Adding #{item_name} (qty: #{total_quantity}) to Sales Order #{sales_order_id}")

    sales_order = Netsuite::SalesOrder.find(sales_order_id)
    return log_error(project_id, "Could not fetch Sales Order for #{item_name} update") unless sales_order

    items = sales_order.dig('item', 'items')&.deep_dup || []

    existing_item = items.find do |item|
      item.dig('item', 'id').to_s == item_id
    end

    if existing_item
      if item_fulfilled?(existing_item)
        log_progress("  #{item_name} already fulfilled (line #{existing_item['line']}, " \
             "qty fulfilled: #{existing_item['quantityFulfilled']}), skipping", level: :warning)
        return
      end
      log_progress("  #{item_name} already exists on SO line #{existing_item['line']}, updating qty to #{total_quantity}")
      existing_item['quantity'] = total_quantity
    else
      new_item = {
        item: { id: item_id },
        quantity: total_quantity,
        amount: 0
      }.merge(extract_class_and_location(items))
      items << new_item
      log_progress("  Added new line item: #{item_name} (qty: #{total_quantity})", level: :success)
    end

    body = {
      item: {
        items: items
      }
    }

    result = Netsuite::SalesOrder.update(sales_order_id, body)
    log_progress("  #{item_name} updated successfully", level: :success)
    result
  rescue StandardError => e
    log_error(project_id, "Error adding #{item_name} to SO: #{e.message}")
    nil
  end

  def add_envoy_items_to_so(project_id, sales_order_id, envoy_items)
    return if envoy_items.empty?

    total_quantity = envoy_items.sum { |item| item[:quantity] }

    log_progress("Adding Enphase Envoy (qty: #{total_quantity}) to Sales Order #{sales_order_id}")

    sales_order = Netsuite::SalesOrder.find(sales_order_id)
    return log_error(project_id, 'Could not fetch Sales Order for Envoy update') unless sales_order

    items = sales_order.dig('item', 'items')&.deep_dup || []

    existing_envoy = items.find do |item|
      item.dig('item', 'id').to_s == ENPHASE_ENVOY_ITEM_ID
    end

    if existing_envoy
      # Skip if item has already been fulfilled
      if item_fulfilled?(existing_envoy)
        log_progress("  Enphase Envoy already fulfilled (line #{existing_envoy['line']}, " \
             "qty fulfilled: #{existing_envoy['quantityFulfilled']}), skipping", level: :warning)
        return
      end
      log_progress("  Enphase Envoy already exists on SO line #{existing_envoy['line']}, updating qty to #{total_quantity}")
      existing_envoy['quantity'] = total_quantity
    else
      new_item = {
        item: { id: ENPHASE_ENVOY_ITEM_ID },
        quantity: total_quantity,
        amount: 0
      }.merge(extract_class_and_location(items))
      items << new_item
      log_progress("  Added new line item: Enphase Envoy (qty: #{total_quantity})", level: :success)
    end

    # Also add ENP CT-200-SPLIT (Item 949) - required with Enphase Envoy
    existing_ct_split = items.find do |item|
      item.dig('item', 'id').to_s == ENP_CT_200_SPLIT_ITEM_ID
    end

    if existing_ct_split
      if item_fulfilled?(existing_ct_split)
        log_progress("  ENP CT-200-SPLIT already fulfilled (line #{existing_ct_split['line']}, " \
             "qty fulfilled: #{existing_ct_split['quantityFulfilled']}), skipping", level: :warning)
      else
        log_progress("  ENP CT-200-SPLIT already exists on SO line #{existing_ct_split['line']}, updating qty to #{total_quantity}")
        existing_ct_split['quantity'] = total_quantity
      end
    else
      ct_split_item = {
        item: { id: ENP_CT_200_SPLIT_ITEM_ID },
        quantity: total_quantity,
        amount: 0
      }.merge(extract_class_and_location(items))
      items << ct_split_item
      log_progress("  Added new line item: ENP CT-200-SPLIT (qty: #{total_quantity})", level: :success)
    end

    body = {
      item: {
        items: items
      }
    }

    result = Netsuite::SalesOrder.update(sales_order_id, body)
    log_progress("  Enphase Envoy items updated successfully", level: :success)
    result
  rescue StandardError => e
    log_error(project_id, "Error adding Envoy to SO: #{e.message}")
    nil
  end

  def handle_combiner_wifi_on_so(project_id, sales_order_id, hdk_items)
    sales_order = Netsuite::SalesOrder.find(sales_order_id)
    return log_error(project_id, 'Could not fetch Sales Order for Combiner-WIFI update') unless sales_order

    items = sales_order.dig('item', 'items')&.deep_dup || []

    existing_combiner = items.find do |item|
      item.dig('item', 'id').to_s == COMBINER_WIFI_5_ITEM_ID
    end

    if hdk_items.any?
      # HDK item present - add or update Combiner-WIFI-5
      total_quantity = hdk_items.sum { |item| item[:quantity] }
      puts "Adding/updating Combiner-WIFI-5 (qty: #{total_quantity}) on Sales Order #{sales_order_id}"

      if existing_combiner
        # Skip if item has already been fulfilled
        if item_fulfilled?(existing_combiner)
          puts "  Combiner-WIFI-5 already fulfilled (line #{existing_combiner['line']}, " \
               "qty fulfilled: #{existing_combiner['quantityFulfilled']}), skipping"
          return
        end
        puts "  Combiner-WIFI-5 already exists on SO (line #{existing_combiner['line']}), updating quantity"
        existing_combiner['quantity'] = total_quantity
      else
        new_item = {
          item: { id: COMBINER_WIFI_5_ITEM_ID },
          quantity: total_quantity,
          amount: 0
        }.merge(extract_class_and_location(items))
        items << new_item
        puts '  Adding new line item for Combiner-WIFI-5'
      end
    elsif existing_combiner
      # Skip removal if item has already been fulfilled
      if item_fulfilled?(existing_combiner)
        puts "  Combiner-WIFI-5 already fulfilled (line #{existing_combiner['line']}), cannot remove"
        return
      end
      # HDK item not present - remove Combiner-WIFI-5 if it exists
      puts "Removing Combiner-WIFI-5 from Sales Order #{sales_order_id} (no X-IQ-AM1-240-5-HDK in BOM)"
      items.reject! { |item| item.dig('item', 'id').to_s == COMBINER_WIFI_5_ITEM_ID }
    else
      puts 'No Combiner-WIFI-5 to remove (not present on SO)'
      return
    end

    body = {
      item: {
        items: items
      }
    }

    # Use replace_item: true to ensure items can be removed, not just merged
    result = Netsuite::SalesOrder.update(sales_order_id, body, replace_item: true)
    puts "Combiner-WIFI-5 update result: #{result}"
    result
  rescue StandardError => e
    log_error(project_id, "Error handling Combiner-WIFI on SO: #{e.message}")
    nil
  end

  def fetch_sales_order_id(project_id)
    # Use NetSuite external ID lookup directly (more reliable than HubSpot)
    external_id = "sales_order_#{project_id}"
    sales_order = Netsuite::SalesOrder.find_external(external_id)
    sales_order['id']&.to_i
  rescue StandardError => e
    puts "Error fetching sales order ID: #{e.message}"
    nil
  end

  def update_racking_quantities(project_id, sales_order_id, sales_order, racking_items)
    # Get the items from the sales order
    so_items = sales_order.dig('item', 'items') || []

    if so_items.empty?
      log_error(project_id, 'Sales Order has no items')
      return
    end

    # Pre-fetch all inventory item details to avoid repeated API calls
    puts "Pre-fetching inventory item details for #{so_items.size} items..."
    item_details_cache = build_item_details_cache(so_items)

    # Build a hash of aggregated quantities by SO line
    # This handles cases where multiple BOM items map to the same SO item
    # (e.g., PSR-HEC and PSR-MCZ-US both map to PSR-MCZ-US (DOMESTIC))
    line_quantities = {}

    racking_items.each do |racking_item|
      bom_part_number = racking_item[:part_number]
      bom_quantity = racking_item[:quantity]

      # PSR-B84 maps to PSR-M168-US (DOMESTIC) at half quantity
      bom_quantity = (bom_quantity / 2.0).ceil if bom_part_number == 'PSR-B84'

      # Find matching item in Sales Order
      matching_so_item = find_matching_so_item(so_items, bom_part_number, item_details_cache)

      if matching_so_item
        line_number = matching_so_item['line']
        so_part_number = get_part_number_from_item(matching_so_item, item_details_cache)
        current_quantity = matching_so_item['quantity'].to_i

        # Skip if line item has already been fulfilled
        if item_fulfilled?(matching_so_item)
          puts "  Skipping fulfilled item: BOM #{bom_part_number} -> SO line #{line_number} " \
               "(quantityFulfilled: #{matching_so_item['quantityFulfilled']})"
          next
        end

        puts "  Match found: BOM #{bom_part_number} (qty: #{bom_quantity}) -> SO line #{line_number} " \
             "#{so_part_number} (current qty: #{current_quantity})"

        # Aggregate quantities for items that map to the same SO line
        if line_quantities[line_number]
          line_quantities[line_number][:new_quantity] += bom_quantity
          puts "    Aggregating with existing quantity: total now #{line_quantities[line_number][:new_quantity]}"
        else
          line_quantities[line_number] = {
            line: line_number,
            part_number: so_part_number,
            old_quantity: current_quantity,
            new_quantity: bom_quantity
          }
        end
      else
        puts "  WARNING: No matching item found in Sales Order for #{bom_part_number}"
      end
    end

    # Build updates needed (only where quantity changed)
    updates_needed = line_quantities.values.reject do |update|
      update[:old_quantity] == update[:new_quantity]
    end

    if updates_needed.empty?
      puts 'No quantity updates needed - all quantities already match'
      return
    end

    # Apply updates to Sales Order
    apply_quantity_updates(sales_order_id, sales_order, updates_needed)
  end

  def build_item_details_cache(so_items)
    cache = {}

    so_items.each do |item|
      item_id = item.dig('item', 'id')
      next unless item_id
      next if cache.key?(item_id) # Skip if already cached (even if value is nil)

      # Use raise_on_not_found: false to skip retries and return nil for non-inventory items
      inventory_item = Netsuite::InventoryItem.find(item_id, raise_on_not_found: false)
      cache[item_id] = inventory_item
    end

    log_progress("Cached #{cache.size} inventory items")
    cache
  end

  def find_matching_so_item(so_items, bom_part_number, item_details_cache)
    # First try exact match
    match = so_items.find do |item|
      so_part = get_part_number_from_item(item, item_details_cache)
      so_part == bom_part_number
    end

    return match if match

    # Try matching with -US (DOMESTIC) suffix
    match = so_items.find do |item|
      so_part = get_part_number_from_item(item, item_details_cache)
      # Check if SO part is domestic version (ends with -US (DOMESTIC))
      normalized_so_part = so_part.gsub(/ \(DOMESTIC\)$/i, '')
      normalized_so_part == bom_part_number
    end

    return match if match

    # Handle specific part number mappings between NetSuite and BOM
    # PSR-M168-US (DOMESTIC) in NetSuite matches PSR-B168 in BOM
    # PSR-MCZ-US (DOMESTIC) in NetSuite matches PSR-MCB in BOM
    # PSR-M168-US (DOMESTIC) in NetSuite also matches PSR-B84 in BOM (at half quantity)
    so_items.find do |item|
      so_part = get_part_number_from_item(item, item_details_cache)
      case bom_part_number
      when 'PSR-B168'
        so_part == 'PSR-M168-US (DOMESTIC)'
      when 'PSR-B84'
        so_part == 'PSR-M168-US (DOMESTIC)'
      when 'PSR-MCB'
        so_part == 'PSR-MCZ-US (DOMESTIC)'
      when 'PSR-MCZ-US'
        so_part == 'PSR-MCZ-US (DOMESTIC)'
      when 'PSR-HEC'
        so_part == 'PSR-MCZ-US (DOMESTIC)'
      when 'PSR-B168-US'
        so_part == 'PSR-M168-US (DOMESTIC)'
      when 'PSR-SPL'
        so_part == 'PSR-SPLS-US (DOMESTIC)'
      when 'PSR-SPLS-US'
        so_part == 'PSR-SPLS-US (DOMESTIC)'
      when 'PSR-MLP-US'
        so_part == 'PSR-MLP-US (DOMESTIC)'
      when 'PSR-SRC'
        so_part == 'PSR-SRC-US (DOMESTIC)'
      when 'PSR-SRC-US'
        so_part == 'PSR-SRC-US (DOMESTIC)'
      else
        false
      end
    end
  end

  def get_part_number_from_item(so_item, item_details_cache)
    # Try to get the item details to find part number
    item_id = so_item.dig('item', 'id')

    if item_id && item_details_cache[item_id]
      # Use cached inventory item
      inventory_item = item_details_cache[item_id]
      part_number = inventory_item['itemId'] || inventory_item['name']
      return part_number if part_number
    end

    # Fallback to item name from SO
    so_item.dig('item', 'refName') || so_item['itemName'] || ''
  end

  def apply_quantity_updates(sales_order_id, sales_order, updates)
    puts "\nApplying #{updates.size} quantity updates to Sales Order #{sales_order_id}:"

    updates.each do |update|
      puts "  Line #{update[:line]}: #{update[:part_number]} - #{update[:old_quantity]} -> #{update[:new_quantity]}"
    end

    # Build the update body with modified item quantities
    items = sales_order.dig('item', 'items').deep_dup

    updates.each do |update|
      item = items.find { |i| i['line'] == update[:line] }
      item['quantity'] = update[:new_quantity] if item
    end

    body = {
      item: {
        items: items
      }
    }

    # Update the Sales Order
    result = Netsuite::SalesOrder.update(sales_order_id, body)
    puts "Sales Order update result: #{result}"
    result
  end

  def item_fulfilled?(item)
    (item['quantityFulfilled'] || 0).to_i.positive?
  end

  def extract_class_and_location(items)
    # Get class and location from the first item on the SO
    first_item = items.first
    return {} unless first_item

    result = {}
    result['class'] = first_item['class'] if first_item['class']
    result['location'] = first_item['location'] if first_item['location']
    result
  end

  def log_error(project_id, message)
    puts "ERROR [Project #{project_id}]: #{message}"
    nil
  end
end
