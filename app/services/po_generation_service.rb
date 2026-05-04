class PoGenerationService
  CED_DIRECT_PAY_VENDOR_ID = 2_660_586
  CED_VENDOR_ID = 1054

  attr_reader :job_record

  def initialize(job_record)
    @job_record = job_record
  end

  # Broadcast log message via ActionCable and save to database
  def log_progress(message, level: :info)
    timestamp = Time.current.strftime("%H:%M:%S")
    log_entry = {
      timestamp: timestamp,
      level: level.to_s,
      message: message,
      job_id: job_record.id
    }

    # Save to database
    PoGenerationLog.create!(
      po_generation_job: job_record,
      level: level.to_s,
      message: message
    )

    # Broadcast to ActionCable
    ActionCable.server.broadcast(
      "po_generation_#{job_record.id}",
      log_entry
    )
  end

  # Generate PO for a single project
  def generate_po_for_project(project_id, skip_email: false, skip_crew_check: false)
    log_progress("Fetching project data for #{project_id}")

    fields = ['name', 'fields.lightreach_direct_pay_po_link', 'fields.loan_application_id',
              'fields.system_size', 'fields.lender']
    result = ProjectSunriseApi.get_projects_bulk([project_id], fields: fields)
    project = result['items']&.first

    unless project
      log_progress("Could not find project #{project_id}", level: :error)
      return nil
    end

    # Fetch job start dates
    log_progress("Fetching job start dates for #{project_id}")
    job_starts = fetch_job_starts_for_projects([project_id])
    project['job_start'] = job_starts[project_id]

    # Create or use existing PO
    po_result = create_po(project, skip_crew_check: skip_crew_check)

    if po_result
      log_progress("Successfully created/retrieved PO for #{project_id}", level: :success)
    else
      log_progress("Failed to create PO for #{project_id}", level: :error)
    end

    po_result
  rescue StandardError => e
    log_progress("Error generating PO for #{project_id}: #{e.message}", level: :error)
    raise
  end

  # Generate POs for an entire region
  def generate_pos_for_region(region_name)
    log_progress("Starting PO generation for region: #{region_name}")

    log_progress("Fetching installations on schedule")
    installations = fetch_installations_on_schedule

    log_progress("Filtering for direct pay projects")
    direct_pay_projects = filter_for_direct_pay(installations)

    log_progress("Found #{direct_pay_projects.length} Lightreach direct pay projects on schedule")

    # Pre-filter projects by region
    log_progress("Filtering projects for #{region_name} region")
    region_projects = []

    direct_pay_projects.each do |project|
      project_id = project['_id']
      so_data = fetch_sales_order_data(project_id)
      location_name = location_name_for(so_data&.dig(:location_id))

      if location_name == region_name
        log_progress("#{region_name} project: #{project_id} - #{project['name']}")
        region_projects << project
      else
        log_progress("Skipping #{location_name} project: #{project_id}")
      end
    end

    log_progress("Processing #{region_projects.length} #{region_name} projects")

    # Create POs for region projects
    created_pos = []
    region_projects.each_with_index do |project, index|
      # Check if job was cancelled
      if job_record.reload.cancelled?
        log_progress("Job was cancelled, stopping region PO generation", level: :warning)
        break
      end

      project_id = project['_id']
      log_progress("Processing project #{index + 1}/#{region_projects.length}: #{project_id}")

      result = create_po(project)
      created_pos << result if result
    end

    log_progress("Successfully created #{created_pos.length} POs for #{region_name}", level: :success)
    created_pos
  rescue StandardError => e
    log_progress("Error generating POs for region #{region_name}: #{e.message}", level: :error)
    raise
  end

  # Generate POs for a batch of projects
  def generate_pos_for_batch(project_ids)
    log_progress("Starting batch PO generation for #{project_ids.length} projects")

    fields = ['name', 'fields.lightreach_direct_pay_po_link', 'fields.loan_application_id',
              'fields.system_size', 'fields.lender']
    result = ProjectSunriseApi.get_projects_bulk(project_ids, fields: fields)
    projects = result['items'] || []

    if projects.empty?
      log_progress("No projects found for provided IDs", level: :error)
      return []
    end

    log_progress("Fetching job start dates for #{projects.length} projects")
    job_starts = fetch_job_starts_for_projects(project_ids)

    created_pos = []
    projects.each_with_index do |project, index|
      # Check if job was cancelled
      if job_record.reload.cancelled?
        log_progress("Job was cancelled, stopping batch PO generation", level: :warning)
        break
      end

      project_id = project['_id']
      project['job_start'] = job_starts[project_id]

      log_progress("Processing project #{index + 1}/#{projects.length}: #{project_id}")
      po_result = create_po(project)
      created_pos << po_result if po_result
    end

    log_progress("Successfully created #{created_pos.length} POs", level: :success)
    created_pos
  rescue StandardError => e
    log_progress("Error in batch PO generation: #{e.message}", level: :error)
    raise
  end

  private

  # Core PO creation logic
  def create_po(project, skip_crew_check: false)
    project_id = project['_id']
    project_name = project['name']
    lightreach_account_id = project.dig('fields', 'loan_application_id')
    job_start = project['job_start']
    existing_po_link = project.dig('fields', 'lightreach_direct_pay_po_link')
    is_direct_pay = direct_pay?(project)

    # Skip if Crew Installation Complete is already done
    system_size = project.dig('fields', 'system_size')
    skip_due_to_system_size = system_size.present? && system_size.to_f.zero?

    if !skip_crew_check && !skip_due_to_system_size && crew_installation_complete?(project_id)
      log_progress("Skipping #{project_id} - Crew Installation Complete already done", level: :warning)
      return nil
    end

    # Check if project already has a PO
    if existing_po_link.present?
      log_progress("Project #{project_id} has existing PO link")
      return use_existing_po(project_id, project_name, lightreach_account_id, job_start, existing_po_link)
    end

    log_progress("Creating new PO for #{project_id} (direct_pay: #{is_direct_pay})")

    # Add racking quantities to sales order
    log_progress("Adding racking quantities to SO for #{project_id}")
    add_racking_quantities_to_so(project_id)

    # Fetch sales order data
    log_progress("Fetching sales order data for #{project_id}")
    so_data = fetch_sales_order_data(project_id)
    unless so_data
      log_progress("Could not fetch Sales Order data for #{project_id}", level: :error)
      return nil
    end

    # Filter PO eligible items
    po_items = filter_po_eligible_items(so_data[:so_items])
    if po_items.empty?
      log_progress("No eligible items found for PO on #{project_id}", level: :warning)
      return nil
    end

    log_progress("Found #{po_items.length} eligible items for PO")

    # Determine vendor based on direct pay status
    if is_direct_pay
      vendor_id = CED_DIRECT_PAY_VENDOR_ID
      vendor_name = 'CED - Direct Pay'
      po_name = "#{project_id} - Lightreach CED Direct Pay"
    else
      vendor_id = CED_VENDOR_ID
      vendor_name = 'CED'
      po_name = "#{project_id} - CED Kitted Job"
    end

    # Submit PO to NetSuite
    log_progress("Submitting PO to NetSuite for #{project_id}")
    po_id = submit_po_to_netsuite(project_id, project_name, po_name, po_items, so_data,
                                  vendor_id: vendor_id, vendor_name: vendor_name,
                                  is_direct_pay: is_direct_pay)

    return nil unless po_id

    log_progress("Created PO #{po_id} for #{project_id}", level: :success)

    # Return PO data
    {
      project_id: project_id,
      project_name: project_name,
      po_id: po_id,
      po_name: po_name,
      po_items: po_items,
      lightreach_account_id: lightreach_account_id,
      job_start: job_start,
      location_id: so_data[:location_id],
      location_name: location_name_for(so_data[:location_id])
    }
  rescue StandardError => e
    log_progress("Error creating PO for #{project_id}: #{e.message}", level: :error)
    nil
  end

  # Use existing PO (verify it exists and hasn't been received)
  def use_existing_po(project_id, project_name, lightreach_account_id, job_start, po_link)
    po_id = extract_po_id_from_link(po_link)
    unless po_id
      log_progress("Could not extract PO ID from link for #{project_id}", level: :error)
      return nil
    end

    log_progress("Verifying existing PO #{po_id} for #{project_id}")

    # Check if racking quantities need to be added
    if racking_quantities_zeroed?(project_id)
      log_progress("Racking quantities zeroed on SO for #{project_id} - adding racking")
      add_racking_quantities_to_so(project_id)
    end

    # Fetch existing PO from NetSuite to verify it exists
    log_progress("Fetching PO #{po_id} from NetSuite")
    purchase_order = Netsuite::PurchaseOrder.find(po_id)

    unless purchase_order.is_a?(Hash)
      log_progress("Could not fetch existing PO #{po_id} for #{project_id}", level: :error)
      return nil
    end

    # Check if PO has already been received
    if po_already_received?(purchase_order)
      log_progress("PO #{po_id} has already been received - skipping", level: :warning)
      return nil
    end

    log_progress("Using existing PO #{po_id} for #{project_id}", level: :success)

    location_id = purchase_order.dig('location', 'id')
    po_items = extract_items_from_po(purchase_order)

    {
      project_id: project_id,
      project_name: project_name,
      po_id: po_id,
      po_name: purchase_order['tranId'] || "#{project_id} - Lightreach CED Direct Pay",
      po_items: po_items,
      lightreach_account_id: lightreach_account_id,
      job_start: job_start,
      location_id: location_id,
      location_name: location_name_for(location_id),
      existing_po: true
    }
  rescue StandardError => e
    log_progress("Error using existing PO for #{project_id}: #{e.message}", level: :error)
    nil
  end

  def fetch_installations_on_schedule
    start_time = Time.now.end_of_week
    end_time = Time.now.end_of_week + 7.days

    installation_jobs = SkeduloApi.find_jobs('Installation', start_time: start_time, end_time: end_time)
    powerwall_jobs = SkeduloApi.find_jobs('Tesla Powerwall', start_time: start_time, end_time: end_time)

    installation_jobs + powerwall_jobs
  end

  def fetch_job_starts_for_projects(project_ids)
    job_starts = {}

    project_ids.each do |project_id|
      installation_jobs = SkeduloApi.list_jobs_for_project(project_id, 'Installation')
      powerwall_jobs = SkeduloApi.list_jobs_for_project(project_id, 'Tesla Powerwall')

      all_starts = (installation_jobs + powerwall_jobs).map { |job| job['Start'] }.compact
      job_starts[project_id] = all_starts.min
    end

    job_starts
  end

  def filter_for_direct_pay(jobs)
    # Build mapping of project_id to job start date
    job_start_by_project = {}
    jobs.each do |job|
      project_id = job.dig('node', 'ProjectSunriseID')
      next unless project_id

      start_date = job.dig('node', 'Start')
      if start_date && (!job_start_by_project[project_id] || start_date < job_start_by_project[project_id])
        job_start_by_project[project_id] = start_date
      end
    end

    project_ids = jobs.map { |job| job['node']['ProjectSunriseID'] }.uniq
    fields = [
      'fields.lender',
      'fields.lightreach_direct_pay',
      'fields.lightreach_direct_pay_po_link',
      'name',
      'fields.loan_application_id',
      'fields.market_region',
      'fields.system_size'
    ]
    result = ProjectSunriseApi.get_projects_bulk(project_ids, fields: fields)
    projects = result['items'] || []
    filtered = projects.select { |project| direct_pay?(project) }

    # Exclude projects where Crew Installation Complete is done
    filtered_ids = filtered.map { |p| p['_id'] }
    crew_complete_ids = SunriseTask.where(
      name: 'Crew Installation Complete',
      is_complete: true,
      project_id: filtered_ids
    ).pluck(:project_id)

    filtered = filtered.reject do |p|
      system_size = p.dig('fields', 'system_size')
      next false if system_size.present? && system_size.to_f.zero?
      crew_complete_ids.include?(p['_id'])
    end

    # Add job start date to each project
    filtered.each do |project|
      project['job_start'] = job_start_by_project[project['_id']]
    end

    filtered
  end

  def direct_pay?(project)
    project.dig('fields', 'lender') == 'Lightreach Lease'
  end

  def crew_installation_complete?(project_id)
    SunriseTask.exists?(
      name: 'Crew Installation Complete',
      is_complete: true,
      project_id: project_id
    )
  end

  def extract_po_id_from_link(po_link)
    return nil if po_link.blank?
    match = po_link.match(/[?&]id=(\d+)/)
    match[1].to_i if match
  end

  def po_already_received?(purchase_order)
    status = purchase_order.dig('status', 'id')
    received_statuses = %w[partiallyReceived pendingBilling fullyBilled closed]
    received_statuses.include?(status)
  end

  def extract_items_from_po(purchase_order)
    po_items = []
    items = purchase_order.dig('item', 'items') || []

    items.each do |item|
      item_id = item.dig('item', 'id')
      next unless item_id

      # Use raise_on_not_found: false to skip retries and return nil for non-inventory items
      inventory_item = Netsuite::InventoryItem.find(item_id, raise_on_not_found: false)
      next unless inventory_item.is_a?(Hash)

      category = inventory_item.dig('custitem1', 'id')&.to_i
      quantity = item['quantity'].to_i
      next if quantity.zero?

      po_items << {
        item_id: item_id,
        part_number: inventory_item['itemId'] || inventory_item['name'],
        quantity: quantity,
        category: category,
        so_line_number: item['line']
      }
    end

    po_items
  end

  def fetch_sales_order_data(project_id)
    sales_order_id = fetch_sales_order_id(project_id)
    return nil unless sales_order_id

    sales_order = Netsuite::SalesOrder.find(sales_order_id)
    return nil unless sales_order

    {
      sales_order_id: sales_order_id,
      customer_id: sales_order.dig('entity', 'id'),
      internal_project_id: sales_order.dig('job', 'id'),
      location_id: sales_order.dig('location', 'id'),
      ship_to_address: sales_order['shipAddress'],
      so_items: sales_order.dig('item', 'items') || []
    }
  end

  def fetch_sales_order_id(project_id)
    external_id = "sales_order_#{project_id}"
    sales_order = Netsuite::SalesOrder.find_external(external_id)
    sales_order['id']&.to_i
  rescue StandardError => e
    log_progress("Error fetching sales order ID for #{project_id}: #{e.message}", level: :error)
    nil
  end

  def submit_po_to_netsuite(project_id, _project_name, po_name, po_items, so_data,
                            vendor_id: CED_DIRECT_PAY_VENDOR_ID, vendor_name: 'CED - Direct Pay',
                            is_direct_pay: true)
    po = Netsuite::PurchaseOrder.new(
      vendor: vendor_id,
      vendor_name: vendor_name,
      customer_id: so_data[:customer_id],
      project_id: project_id,
      internal_project_id: so_data[:internal_project_id],
      location_id: so_data[:location_id],
      tran_id: po_name,
      customer_ship_to: so_data[:ship_to_address]
    )

    po_items.each do |item|
      po.add_item(id: item[:item_id], quantity: item[:quantity], amount: is_direct_pay ? 0 : nil)
    end

    po_id = po.create
    log_progress("Created PO '#{po_name}' with ID: #{po_id}", level: :success)

    if po_id
      po_link = build_po_link(po_id)
      update_project_po_link(project_id, po_link)
    end

    po_id
  rescue StandardError => e
    log_progress("Failed to create PO '#{po_name}': #{e.message}", level: :error)
    nil
  end

  def build_po_link(po_id)
    environment = Rails.env.production? ? :production : :sandbox
    account_id = Rails.application.credentials.dig(:netsuite, environment, :account_id_url)
    "https://#{account_id}.app.netsuite.com/app/accounting/transactions/purchord.nl?id=#{po_id}"
  end

  def update_project_po_link(project_id, po_link)
    updates = {
      'lightreach_direct_pay_po_link' => po_link,
      'lightreach_direct_pay_po_creation_date' => Time.now.to_i * 1000
    }
    ProjectSunriseApi.update_project(project_id, updates)
    log_progress("Updated project #{project_id} with PO link")
  end

  def filter_po_eligible_items(so_items)
    eligible_categories = [2, 3, 5, 18, 21, 33]
    po_items = []

    so_items.each do |item|
      item_id = item.dig('item', 'id')
      next unless item_id

      # Use raise_on_not_found: false to skip retries and return nil for non-inventory items
      inventory_item = Netsuite::InventoryItem.find(item_id, raise_on_not_found: false)
      next unless inventory_item.is_a?(Hash)

      category = inventory_item.dig('custitem1', 'id')&.to_i
      next unless eligible_categories.include?(category)

      quantity = item['quantity'].to_i
      next if quantity.zero?

      po_items << {
        item_id: item_id,
        part_number: inventory_item['itemId'] || inventory_item['name'],
        quantity: quantity,
        category: category,
        so_line_number: item['line']
      }
    end

    po_items
  end

  def add_racking_quantities_to_so(project_id)
    log_progress("Running racking quantities worker for #{project_id}")
    AddRackingQuantitiesToSoWorker.new.perform(project_id, skip_status_check: true)
  rescue StandardError => e
    log_progress("Error adding racking quantities: #{e.message}", level: :warning)
  end

  def racking_quantities_zeroed?(project_id)
    so_data = fetch_sales_order_data(project_id)
    return true unless so_data

    so_items = so_data[:so_items] || []
    return true if so_items.empty?

    psr_m168_item = so_items.find do |item|
      item_id = item.dig('item', 'id')
      next false unless item_id

      # Use raise_on_not_found: false to skip retries and return nil for non-inventory items
      inventory_item = Netsuite::InventoryItem.find(item_id, raise_on_not_found: false)
      next false unless inventory_item.is_a?(Hash)

      part_number = inventory_item['itemId'] || inventory_item['name']
      part_number == 'PSR-M168-US (DOMESTIC)'
    end

    return true unless psr_m168_item

    quantity = psr_m168_item['quantity'].to_i
    quantity <= 0
  end

  def location_name_for(location_id)
    {
      1 => 'Austin',
      2 => 'Houston',
      3 => 'Dallas',
      4 => 'San Antonio',
      5 => 'Denver',
      6 => 'Co Springs',
      7 => 'Tampa',
      17 => 'Norfolk',
      18 => 'Orlando',
      19 => 'Charlotte',
      20 => 'Raleigh',
      25 => 'HQ',
      28 => 'Commercial'
    }[location_id&.to_i] || "Location #{location_id}"
  end

  def category_name_for(category_id)
    {
      2 => 'Modules',
      3 => 'Racking',
      5 => 'Monitoring',
      18 => 'Energy Storage',
      21 => 'Inverters'
    }[category_id] || 'Other'
  end

  def aggregate_items_across_projects(created_pos)
    item_totals = {}

    created_pos.each do |po_data|
      po_data[:po_items].each do |item|
        part_number = item[:part_number]
        if item_totals[part_number]
          item_totals[part_number][:quantity] += item[:quantity]
        else
          item_totals[part_number] = {
            part_number: part_number,
            category: item[:category],
            category_name: category_name_for(item[:category]),
            quantity: item[:quantity]
          }
        end
      end
    end

    # Sort by category then part number
    item_totals.values.sort_by { |item| [item[:category] || 999, item[:part_number]] }
  end

  public

  def generate_location_summary_pdf(location_pos, location_name)
    require 'prawn'
    require 'prawn/table'

    aggregated_items = aggregate_items_across_projects(location_pos)

    Prawn::Document.new do |pdf|
      pdf.font_size 20
      pdf.text "Lightreach Direct Pay - #{location_name} Summary", style: :bold
      pdf.move_down 10

      pdf.font_size 10
      pdf.text "Generated: #{Time.now.strftime('%B %d, %Y at %I:%M %p')}"
      pdf.text "Total Projects: #{location_pos.length}"
      pdf.move_down 20

      # Aggregated items section
      pdf.font_size 16
      pdf.text 'Aggregated Items', style: :bold
      pdf.move_down 10

      aggregated_table = [['Part Number', 'Category', 'Total Quantity']]
      aggregated_items.each do |item|
        aggregated_table << [item[:part_number], item[:category_name], item[:quantity].to_s]
      end

      pdf.font_size 10
      pdf.table(aggregated_table, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = 'CCCCCC'
        columns(2).align = :center
      end

      grand_total = aggregated_items.sum { |item| item[:quantity] }
      pdf.move_down 5
      pdf.text "Grand Total: #{grand_total} items", style: :bold

      # Individual project breakdowns
      pdf.start_new_page
      pdf.font_size 16
      pdf.text 'Project Details', style: :bold
      pdf.move_down 15

      location_pos.each_with_index do |po_data, index|
        pdf.font_size 14
        pdf.text "Project: #{po_data[:project_name]}", style: :bold
        pdf.font_size 10
        pdf.text "Project ID: #{po_data[:project_id]}"
        pdf.text "PO ID: #{po_data[:po_id]}"
        pdf.move_down 10

        table_data = [['Part Number', 'Category', 'Quantity']]
        po_data[:po_items].each do |item|
          category_name = category_name_for(item[:category])
          table_data << [item[:part_number], category_name, item[:quantity].to_s]
        end

        pdf.table(table_data, header: true, width: pdf.bounds.width) do
          row(0).font_style = :bold
          row(0).background_color = 'DDDDDD'
          columns(2).align = :center
        end

        pdf.move_down 20
        pdf.start_new_page if index < location_pos.length - 1
      end
    end.render
  end

  def upload_po_to_lightreach(po_data, pdf_binary)
    account_id = po_data[:lightreach_account_id]
    filename = "#{po_data[:po_name]}.pdf"

    # Create a temporary file for the PDF
    temp_file = Tempfile.new(['po', '.pdf'], binmode: true)
    temp_file.write(pdf_binary)
    temp_file.rewind

    # Prepare the document structure for Lightreach
    document = {
      type: 'billOfMaterials',
      grouped: true,
      files: [
        {
          'file' => temp_file,
          'filename' => filename
        }
      ]
    }

    result = Lightreach::Document.upload(account_id, document)
    log_progress("Uploaded PO #{po_data[:po_id]} to Lightreach account #{account_id}")
    result
  rescue StandardError => e
    log_progress("Failed to upload PO #{po_data[:po_id]} to Lightreach: #{e.message}", level: :error)
    nil
  ensure
    temp_file&.close
    temp_file&.unlink
  end
end
