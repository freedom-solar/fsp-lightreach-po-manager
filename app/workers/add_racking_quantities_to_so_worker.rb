require "pdf-reader"

class AddRackingQuantitiesToSoWorker
  include Sidekiq::Worker

  sidekiq_options queue: "po_generation", retry: 3

  # NetSuite item ID for Tesla Mid-Circuit Interrupter Gen2
  TESLA_MCI_GEN2_ITEM_ID = "939"
  # NetSuite item ID for Enphase Envoy
  ENPHASE_ENVOY_ITEM_ID = "941"
  # NetSuite item ID for ENP CT-200-SPLIT (required with Enphase Envoy)
  ENP_CT_200_SPLIT_ITEM_ID = "949"
  # NetSuite item ID for Combiner-WIFI-5
  COMBINER_WIFI_5_ITEM_ID = "734"
  # NetSuite item ID for PF-DW75 (Pegasus non-standard racking)
  PF_DW75_ITEM_ID = "948"
  # NetSuite item ID for PIF2-BDT (Pegasus non-standard racking)
  PIF2_BDT_ITEM_ID = "947"
  # PF-SF70 ITEM ID (Pegasus non-standard racking)
  PF_SF70_ITEM_ID = "956"
  # NetSuite item ID for Tesla 200A CT
  TESLA_200A_CT_ITEM_ID = "953"
  # NetSuite item ID for SUNMODO TOPTILE-7-B
  SUNMODO_TOPTILE_7_B_ITEM_ID = "954"
  # NetSuite item ID for SPAN 1-00800-XX
  SPAN_1_00800_XX_ITEM_ID = "735"
  # NetSuite item ID for PL7R-40MID200-FG
  PL7R_40MID200_FG_ITEM_ID = "855"
  # NetSuite item ID for Tesla Remote Energy Meter
  TESLA_METER_ITEM_ID = "787"
  # NetSuite item ID for APKE00084
  APKE00084_ITEM_ID = "957"
  # NetSuite item ID for APKE00086
  APKE00086_ITEM_ID = "958"
  # NetSuite item ID for APKE00088
  APKE00088_ITEM_ID = "959"
  # NetSuite item ID for APKE00090
  APKE00090_ITEM_ID = "960"
  # NetSuite item ID for APKE00091
  APKE00091_ITEM_ID = "961"
  # NetSuite item ID for APKE00092
  APKE00092_ITEM_ID = "962"
  # NetSuite item ID for APKE00094
  APKE00094_ITEM_ID = "963"
  # NetSuite item ID for APKE00096
  APKE00096_ITEM_ID = "964"
  # NetSuite item ID for APKE00098
  APKE00098_ITEM_ID = "965"
  # NetSuite item ID for APKE00100
  APKE00100_ITEM_ID = "966"
  # NetSuite item ID for APKE00102
  APKE00102_ITEM_ID = "967"
  # NetSuite item ID for APKE00105
  APKE00105_ITEM_ID = "968"
  # NetSuite item ID for APKE00110
  APKE00110_ITEM_ID = "969"
  # NetSuite item ID for APKE00115
  APKE00115_ITEM_ID = "970"
  # NetSuite item ID for Generac PWRmanager (G0080090-PC2)
  GENERAC_PWR_MANAGER_ITEM_ID = "972"
  # NetSuite item ID for PWRMICRO SMART COMBINER (APKEAC100)
  PWRMICRO_SMART_COMBINER_ITEM_ID = "928"
  # NetSuite item ID for PWRMICRO PM-820-US 820W DUAL INPUT (APKEPM820)
  PWRMICRO_PM_820_US_ITEM_ID = "929"

  # BOM items to parse and add to SO (standard flow)
  BOM_ITEM_CONFIGS = [
    { search_string: "TESLA MID-CIRCUIT INTERRUPTER GEN2", item_id: TESLA_MCI_GEN2_ITEM_ID,
      item_name: "Tesla MCI Gen2" },
    { search_string: "PF-DW75", item_id: PF_DW75_ITEM_ID, item_name: "PF-DW75" },
    { search_string: "PIF2-BDT", item_id: PIF2_BDT_ITEM_ID, item_name: "PIF2-BDT" },
    { search_string: "2033376-", item_id: TESLA_200A_CT_ITEM_ID, item_name: "Tesla 200A CT" },
    { search_string: "K10461-107-BK", item_id: SUNMODO_TOPTILE_7_B_ITEM_ID, item_name: "SUNMODO TOPTILE-7-B" },
    { search_string: "PF-SF70", item_id: PF_SF70_ITEM_ID, item_name: "PF-SF70" },
    { search_string: "SPAN 1-00800-XX", item_id: SPAN_1_00800_XX_ITEM_ID, item_name: "SPAN 1-00800-XX" },
    { search_string: "PL7R-40MID200-FG", item_id: PL7R_40MID200_FG_ITEM_ID, item_name: "PL7R-40MID200-FG" },
    { search_string: "2002069-", item_id: TESLA_METER_ITEM_ID, item_name: "Tesla Meter" },
    { search_string: "APKE00084", item_id: APKE00084_ITEM_ID, item_name: "APKE00084" },
    { search_string: "APKE00086", item_id: APKE00086_ITEM_ID, item_name: "APKE00086" },
    { search_string: "APKE00088", item_id: APKE00088_ITEM_ID, item_name: "APKE00088" },
    { search_string: "APKE00090", item_id: APKE00090_ITEM_ID, item_name: "APKE00090" },
    { search_string: "APKE00091", item_id: APKE00091_ITEM_ID, item_name: "APKE00091" },
    { search_string: "APKE00092", item_id: APKE00092_ITEM_ID, item_name: "APKE00092" },
    { search_string: "APKE00094", item_id: APKE00094_ITEM_ID, item_name: "APKE00094" },
    { search_string: "APKE00096", item_id: APKE00096_ITEM_ID, item_name: "APKE00096" },
    { search_string: "APKE00098", item_id: APKE00098_ITEM_ID, item_name: "APKE00098" },
    { search_string: "APKE00100", item_id: APKE00100_ITEM_ID, item_name: "APKE00100" },
    { search_string: "APKE00102", item_id: APKE00102_ITEM_ID, item_name: "APKE00102" },
    { search_string: "APKE00105", item_id: APKE00105_ITEM_ID, item_name: "APKE00105" },
    { search_string: "APKE00110", item_id: APKE00110_ITEM_ID, item_name: "APKE00110" },
    { search_string: "APKE00115", item_id: APKE00115_ITEM_ID, item_name: "APKE00115" },
    { search_string: "G0080090-PC2", item_id: GENERAC_PWR_MANAGER_ITEM_ID, item_name: "Generac PWRmanager" },
    # APKEAC100 also appears inside the descriptions of BR220/BR230 ("WITH ... APKEAC100"),
    # so we anchor the match to the part-number column at the start of the line.
    { search_string: "APKEAC100", item_id: PWRMICRO_SMART_COMBINER_ITEM_ID,
      item_name: "PWRMICRO SMART COMBINER", match_at_line_start: true },
    { search_string: "APKEPM820", item_id: PWRMICRO_PM_820_US_ITEM_ID,
      item_name: "PWRMICRO PM-820-US", match_at_line_start: true }
  ].freeze

  def perform(project_id, job_id: nil, skip_status_check: false)
    @job_id = job_id
    log_progress("Processing project #{project_id} for racking quantities update")

    # Get BOM file from Sunrise
    bom_data = fetch_bom_file(project_id)
    return log_error(project_id, "No BOM file found") unless bom_data["file"]

    # Extract Pegasus racking items from BOM
    racking_items = parse_racking_items_from_bom(bom_data["file"])

    # Get NetSuite Sales Order ID from HubSpot Deal
    sales_order_id = fetch_sales_order_id(project_id)
    return log_error(project_id, "Could not find NetSuite Sales Order ID") unless sales_order_id

    log_progress("Found NetSuite Sales Order ID: #{sales_order_id}")

    # Fetch Sales Order from NetSuite
    sales_order = Netsuite::SalesOrder.find(sales_order_id)
    return log_error(project_id, "Could not fetch Sales Order from NetSuite") unless sales_order

    # NOTE: We check individual line item fulfillment (quantityFulfilled) instead of SO-level status
    # This allows updating unfulfilled items even when other parts of the SO have been fulfilled

    # Update racking quantities on Sales Order (skips fulfilled items) - only if racking items found
    if racking_items.any?
      log_progress("Found #{racking_items.size} Pegasus racking items in BOM")
      racking_items.each { |item| log_progress("  #{item[:part_number]}: #{item[:quantity]} EA") }
      update_racking_quantities(project_id, sales_order_id, sales_order, racking_items)
    else
      log_progress("No Pegasus racking items found in BOM (battery-only job?)", level: :warning)
    end

    # Parse and add Enphase Envoy items (special case: adds 2 items)
    envoy_items = parse_items_from_bom(bom_data["file"], search_string: "ENV-IQ-AM1-240",
                                                         item_name: "Enphase Envoy")
    add_envoy_items_to_so(project_id, sales_order_id, envoy_items) if envoy_items.any?

    # Handle Combiner-WIFI-5 (special case: adds/removes based on HDK presence).
    # Anchor to line start: X-IQ-AM1-240-5-HDK is referenced in the description of
    # BR220 ("WITH X-IQ-AM1-240-5-HDK OR APKEAC100"), so a substring match would
    # add Combiner-WIFI-5 on jobs that don't actually have an HDK row.
    hdk_items = parse_items_from_bom(bom_data["file"], search_string: "X-IQ-AM1-240-5-HDK",
                                                       item_name: "X-IQ-AM1-240-5-HDK",
                                                       match_at_line_start: true)
    handle_combiner_wifi_on_so(project_id, sales_order_id, hdk_items)

    # Parse and add standard BOM items
    BOM_ITEM_CONFIGS.each do |config|
      parse_and_add_item(bom_data["file"], project_id, sales_order_id, **config)
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
    ProjectSunriseApi.get_file(project_id, "BOM")
  end

  def parse_racking_items_from_bom(bom_file)
    racking_items = []

    # Read PDF and extract text
    reader = PDF::Reader.new(bom_file.path)
    text = reader.pages.map(&:text).join("\n")

    # Parse each line looking for Pegasus items
    text.each_line do |line|
      # Look for lines containing "Pegasus" in the description
      next unless line.include?("Pegasus")

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

  def parse_and_add_item(bom_file, project_id, sales_order_id, search_string:, item_id:, item_name:,
                         match_at_line_start: false)
    items = parse_items_from_bom(bom_file, search_string: search_string, item_name: item_name,
                                           match_at_line_start: match_at_line_start)
    add_item_to_so(project_id, sales_order_id, items, item_id: item_id, item_name: item_name) if items.any?
  end

  def parse_items_from_bom(bom_file, search_string:, item_name:, match_at_line_start: false)
    items = []

    reader = PDF::Reader.new(bom_file.path)
    text = reader.pages.map(&:text).join("\n")

    text.each_line do |line|
      if match_at_line_start
        next unless line.lstrip.start_with?(search_string)
      else
        next unless line.include?(search_string)
      end
      # Anchor to end of line: qty/EA is the trailing column in a BOM row.
      # Unanchored matching can grab a digit from the description (e.g. the "5"
      # in "ENPHASE IQ COMBINER 5; WITH ENVOY MONITORING") if PDF text
      # extraction rewrites the punctuation between the digit and "EA".
      next unless line =~ /(\d+)\s+EA\s*$/i

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

    items = sales_order.dig("item", "items")&.deep_dup || []

    existing_item = items.find do |item|
      item.dig("item", "id").to_s == item_id
    end

    if existing_item
      if item_fulfilled?(existing_item)
        log_progress("  #{item_name} already fulfilled (line #{existing_item['line']}, " \
             "qty fulfilled: #{existing_item['quantityFulfilled']}), skipping", level: :warning)
        return
      end
      log_progress("  #{item_name} already exists on SO line #{existing_item['line']}, updating qty to #{total_quantity}")
      existing_item["quantity"] = total_quantity
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
    return log_error(project_id, "Could not fetch Sales Order for Envoy update") unless sales_order

    items = sales_order.dig("item", "items")&.deep_dup || []

    existing_envoy = items.find do |item|
      item.dig("item", "id").to_s == ENPHASE_ENVOY_ITEM_ID
    end

    if existing_envoy
      # Skip if item has already been fulfilled
      if item_fulfilled?(existing_envoy)
        log_progress("  Enphase Envoy already fulfilled (line #{existing_envoy['line']}, " \
             "qty fulfilled: #{existing_envoy['quantityFulfilled']}), skipping", level: :warning)
        return
      end
      log_progress("  Enphase Envoy already exists on SO line #{existing_envoy['line']}, updating qty to #{total_quantity}")
      existing_envoy["quantity"] = total_quantity
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
      item.dig("item", "id").to_s == ENP_CT_200_SPLIT_ITEM_ID
    end

    if existing_ct_split
      if item_fulfilled?(existing_ct_split)
        log_progress("  ENP CT-200-SPLIT already fulfilled (line #{existing_ct_split['line']}, " \
             "qty fulfilled: #{existing_ct_split['quantityFulfilled']}), skipping", level: :warning)
      else
        log_progress("  ENP CT-200-SPLIT already exists on SO line #{existing_ct_split['line']}, updating qty to #{total_quantity}")
        existing_ct_split["quantity"] = total_quantity
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
    return log_error(project_id, "Could not fetch Sales Order for Combiner-WIFI update") unless sales_order

    items = sales_order.dig("item", "items")&.deep_dup || []

    existing_combiner = items.find do |item|
      item.dig("item", "id").to_s == COMBINER_WIFI_5_ITEM_ID
    end

    if hdk_items.any?
      # HDK item present - add or update Combiner-WIFI-5
      total_quantity = hdk_items.sum { |item| item[:quantity] }
      log_progress("Adding/updating Combiner-WIFI-5 (qty: #{total_quantity}) on Sales Order #{sales_order_id}")

      if existing_combiner
        # Skip if item has already been fulfilled
        if item_fulfilled?(existing_combiner)
          log_progress("  Combiner-WIFI-5 already fulfilled (line #{existing_combiner['line']}, " \
               "qty fulfilled: #{existing_combiner['quantityFulfilled']}), skipping", level: :warning)
          return
        end
        log_progress("  Combiner-WIFI-5 already exists on SO line #{existing_combiner['line']}, updating qty to #{total_quantity}")
        existing_combiner["quantity"] = total_quantity
      else
        new_item = {
          item: { id: COMBINER_WIFI_5_ITEM_ID },
          quantity: total_quantity,
          amount: 0
        }.merge(extract_class_and_location(items))
        items << new_item
        log_progress("  Added new line item: Combiner-WIFI-5 (qty: #{total_quantity})", level: :success)
      end
    elsif existing_combiner
      # Skip removal if item has already been fulfilled
      if item_fulfilled?(existing_combiner)
        log_progress("  Combiner-WIFI-5 already fulfilled (line #{existing_combiner['line']}), cannot remove", level: :warning)
        return
      end
      # HDK item not present - remove Combiner-WIFI-5 if it exists
      log_progress("Removing Combiner-WIFI-5 from Sales Order #{sales_order_id} (no X-IQ-AM1-240-5-HDK in BOM)")
      items.reject! { |item| item.dig("item", "id").to_s == COMBINER_WIFI_5_ITEM_ID }
    else
      log_progress("No Combiner-WIFI-5 to remove (not present on SO)")
      return
    end

    body = {
      item: {
        items: items
      }
    }

    # Use replace_item: true to ensure items can be removed, not just merged
    result = Netsuite::SalesOrder.update(sales_order_id, body, replace_item: true)
    log_progress("  Combiner-WIFI-5 updated successfully", level: :success)
    result
  rescue StandardError => e
    log_error(project_id, "Error handling Combiner-WIFI on SO: #{e.message}")
    nil
  end

  def fetch_sales_order_id(project_id)
    # Use NetSuite external ID lookup directly (more reliable than HubSpot)
    external_id = "sales_order_#{project_id}"
    sales_order = Netsuite::SalesOrder.find_external(external_id)
    sales_order["id"]&.to_i
  rescue StandardError => e
    puts "Error fetching sales order ID: #{e.message}"
    nil
  end

  def update_racking_quantities(project_id, sales_order_id, sales_order, racking_items)
    # Get the items from the sales order
    so_items = sales_order.dig("item", "items") || []

    if so_items.empty?
      log_error(project_id, "Sales Order has no items")
      return
    end

    # Pre-fetch all inventory item details to avoid repeated API calls
    log_progress("Pre-fetching inventory item details for #{so_items.size} items")
    item_details_cache = build_item_details_cache(so_items)

    # Build a hash of aggregated quantities by SO line
    # This handles cases where multiple BOM items map to the same SO item
    # (e.g., PSR-HEC and PSR-MCZ-US both map to PSR-MCZ-US (DOMESTIC))
    line_quantities = {}
    unmatched_items = []

    racking_items.each do |racking_item|
      bom_part_number = racking_item[:part_number]
      bom_quantity = racking_item[:quantity]

      # PSR-B84 maps to PSR-M168-US (DOMESTIC) at half quantity
      bom_quantity = (bom_quantity / 2.0).ceil if bom_part_number == "PSR-B84"

      # Find matching item in Sales Order
      matching_so_item = find_matching_so_item(so_items, bom_part_number, item_details_cache)

      if matching_so_item
        line_number = matching_so_item["line"]
        so_part_number = get_part_number_from_item(matching_so_item, item_details_cache)
        current_quantity = matching_so_item["quantity"].to_i

        # Skip if line item has already been fulfilled
        if item_fulfilled?(matching_so_item)
          log_progress("  Skipping fulfilled item: BOM #{bom_part_number} -> SO line #{line_number} " \
                       "(quantityFulfilled: #{matching_so_item['quantityFulfilled']})", level: :warning)
          next
        end

        log_progress("  Match found: BOM #{bom_part_number} (qty: #{bom_quantity}) -> SO line #{line_number} " \
                     "#{so_part_number} (current qty: #{current_quantity})")

        # Aggregate quantities for items that map to the same SO line
        if line_quantities[line_number]
          line_quantities[line_number][:new_quantity] += bom_quantity
          log_progress("    Aggregating with existing quantity: total now #{line_quantities[line_number][:new_quantity]}")
        else
          line_quantities[line_number] = {
            line: line_number,
            part_number: so_part_number,
            old_quantity: current_quantity,
            new_quantity: bom_quantity
          }
        end
      else
        unmatched_items << { part_number: bom_part_number, quantity: bom_quantity }
      end
    end

    # Resolve NetSuite item ids for BOM lines with no matching SO line, and aggregate
    # quantities for any duplicates that resolve to the same NetSuite item.
    new_lines_by_item_id = resolve_new_racking_lines(project_id, unmatched_items)

    # Build updates needed (only where quantity changed)
    updates_needed = line_quantities.values.reject do |update|
      update[:old_quantity] == update[:new_quantity]
    end

    if updates_needed.empty? && new_lines_by_item_id.empty?
      log_progress("No quantity updates or new racking lines needed - all quantities already match")
      return
    end

    # Apply updates to Sales Order
    apply_quantity_updates(sales_order_id, sales_order, updates_needed, new_lines_by_item_id)
  end

  # For unmatched BOM racking items, look up NetSuite item ids and aggregate
  # quantities by id (so multiple BOM lines that map to the same NS item — e.g.,
  # PSR-HEC and PSR-MCZ-US both map to PSR-MCZ-US (DOMESTIC) — get one new line).
  def resolve_new_racking_lines(project_id, unmatched_items)
    return {} if unmatched_items.empty?

    ns_item_ids_by_part = fetch_ns_item_ids_for_bom_parts(unmatched_items.map { |i| i[:part_number] }.uniq)

    new_lines_by_item_id = {}
    unmatched_items.each do |item|
      bom_part_number = item[:part_number]
      ns_item_id = ns_item_ids_by_part[bom_part_number]

      if ns_item_id
        log_progress("  No SO line for BOM #{bom_part_number} - will add new line " \
                     "(NetSuite item id #{ns_item_id}, qty #{item[:quantity]})")
        entry = new_lines_by_item_id[ns_item_id] ||= { quantity: 0, bom_parts: [] }
        entry[:quantity] += item[:quantity]
        entry[:bom_parts] << bom_part_number
      else
        log_progress("  WARNING: No matching SO line and no NetSuite item id resolved for " \
                     "BOM #{bom_part_number} - racking will be missing from PO", level: :warning)
      end
    end
    new_lines_by_item_id
  rescue StandardError => e
    log_error(project_id, "Error resolving NetSuite item ids for new racking lines: #{e.message}")
    {}
  end

  # Look up NetSuite item ids for a list of BOM part numbers. Returns a hash
  # of bom_part_number => netsuite_item_id (integer). Missing entries mean no
  # InvtPart with a matching itemid was found.
  def fetch_ns_item_ids_for_bom_parts(bom_part_numbers)
    candidates_by_bom_part = bom_part_numbers.each_with_object({}) do |bom_part, h|
      h[bom_part] = candidate_ns_part_numbers(bom_part)
    end

    all_candidates = candidates_by_bom_part.values.flatten.uniq
    return {} if all_candidates.empty?

    quoted = all_candidates.map { |c| "'#{c.gsub("'", "''")}'" }.join(",")
    sql = "SELECT id, itemid FROM item WHERE itemtype = 'InvtPart' AND itemid IN (#{quoted})"
    response = Netsuite::Client.new.suiteql(query: sql)
    rows = response["items"] || []
    ns_id_by_part = rows.each_with_object({}) { |row, h| h[row["itemid"]] = row["id"].to_i }

    candidates_by_bom_part.each_with_object({}) do |(bom_part, candidates), result|
      hit = candidates.find { |c| ns_id_by_part[c] }
      result[bom_part] = ns_id_by_part[hit] if hit
    end
  end

  # Ordered list of NetSuite itemid candidates for a BOM part number. The first
  # candidate that exists as an InvtPart wins. Mirrors the explicit mappings used
  # by find_matching_so_item, then tries the "(DOMESTIC)" variant, then the bare
  # part number.
  def candidate_ns_part_numbers(bom_part_number)
    explicit = case bom_part_number
    when "PSR-B168", "PSR-B84", "PSR-B168-US"
      "PSR-M168-US (DOMESTIC)"
    when "PSR-MCB", "PSR-HEC", "PSR-MCZ-US"
      "PSR-MCZ-US (DOMESTIC)"
    when "PSR-SPL", "PSR-SPLS-US"
      "PSR-SPLS-US (DOMESTIC)"
    when "PSR-MLP-US"
      "PSR-MLP-US (DOMESTIC)"
    when "PSR-SRC", "PSR-SRC-US"
      "PSR-SRC-US (DOMESTIC)"
    end
    [ explicit, "#{bom_part_number} (DOMESTIC)", bom_part_number ].compact.uniq
  end

  def build_item_details_cache(so_items)
    item_ids = so_items.map { |i| i.dig("item", "id") }.compact
    cache = Netsuite::InventoryItem.fetch_details_by_ids(item_ids)
    log_progress("Cached #{cache.size} item details")
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
      normalized_so_part = so_part.gsub(/ \(DOMESTIC\)$/i, "")
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
      when "PSR-B168"
        so_part == "PSR-M168-US (DOMESTIC)"
      when "PSR-B84"
        so_part == "PSR-M168-US (DOMESTIC)"
      when "PSR-MCB"
        so_part == "PSR-MCZ-US (DOMESTIC)"
      when "PSR-MCZ-US"
        so_part == "PSR-MCZ-US (DOMESTIC)"
      when "PSR-HEC"
        so_part == "PSR-MCZ-US (DOMESTIC)"
      when "PSR-B168-US"
        so_part == "PSR-M168-US (DOMESTIC)"
      when "PSR-SPL"
        so_part == "PSR-SPLS-US (DOMESTIC)"
      when "PSR-SPLS-US"
        so_part == "PSR-SPLS-US (DOMESTIC)"
      when "PSR-MLP-US"
        so_part == "PSR-MLP-US (DOMESTIC)"
      when "PSR-SRC"
        so_part == "PSR-SRC-US (DOMESTIC)"
      when "PSR-SRC-US"
        so_part == "PSR-SRC-US (DOMESTIC)"
      else
        false
      end
    end
  end

  def get_part_number_from_item(so_item, item_details_cache)
    item_id = so_item.dig("item", "id")&.to_i

    if item_id && item_details_cache[item_id]
      detail = item_details_cache[item_id]
      part_number = detail["itemid"] || detail["displayname"]
      return part_number if part_number
    end

    so_item.dig("item", "refName") || so_item["itemName"] || ""
  end

  def apply_quantity_updates(sales_order_id, sales_order, updates, new_lines_by_item_id = {})
    log_progress("Applying #{updates.size} quantity updates and #{new_lines_by_item_id.size} new racking lines to Sales Order #{sales_order_id}")

    updates.each do |update|
      log_progress("  Line #{update[:line]}: #{update[:part_number]} - #{update[:old_quantity]} -> #{update[:new_quantity]}")
    end

    # Build the update body with modified item quantities
    items = sales_order.dig("item", "items").deep_dup

    updates.each do |update|
      item = items.find { |i| i["line"] == update[:line] }
      item["quantity"] = update[:new_quantity] if item
    end

    if new_lines_by_item_id.any?
      class_and_location = extract_class_and_location(items)
      new_lines_by_item_id.each do |item_id, info|
        new_item = {
          item: { id: item_id.to_s },
          quantity: info[:quantity],
          amount: 0
        }.merge(class_and_location)
        items << new_item
        log_progress("  Added new racking line: NetSuite item #{item_id} qty #{info[:quantity]} " \
                     "(from BOM #{info[:bom_parts].join(', ')})", level: :success)
      end
    end

    body = {
      item: {
        items: items
      }
    }

    # Update the Sales Order
    result = Netsuite::SalesOrder.update(sales_order_id, body)
    log_progress("Sales Order #{sales_order_id} updated", level: :success)
    result
  end

  def item_fulfilled?(item)
    (item["quantityFulfilled"] || 0).to_i.positive?
  end

  def extract_class_and_location(items)
    # Get class and location from the first item on the SO
    first_item = items.first
    return {} unless first_item

    result = {}
    result["class"] = first_item["class"] if first_item["class"]
    result["location"] = first_item["location"] if first_item["location"]
    result
  end

  def log_error(project_id, message)
    puts "ERROR [Project #{project_id}]: #{message}"
    nil
  end
end
