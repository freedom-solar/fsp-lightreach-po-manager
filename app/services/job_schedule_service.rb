class JobScheduleService
  def fetch_jobs_on_schedule(region: nil)
    installations = fetch_installations_on_schedule
    Rails.logger.info "[JobScheduleService] Found #{installations.length} installations on schedule"

    scheduled_projects = fetch_scheduled_projects(installations)
    Rails.logger.info "[JobScheduleService] Found #{scheduled_projects.length} scheduled projects"

    if region
      # Batch fetch all sales orders to avoid N+1 queries
      project_ids = scheduled_projects.map { |p| p["_id"] }
      location_map = batch_fetch_project_locations(project_ids)

      filtered = scheduled_projects.select do |project|
        location_name = location_map[project["_id"]]
        Rails.logger.info "[JobScheduleService] Project #{project['_id']}: location_name=#{location_name}, target_region=#{region}, match=#{location_name == region}"
        location_name == region
      end

      Rails.logger.info "[JobScheduleService] Found #{filtered.length} projects for region: #{region}"
      filtered
    else
      scheduled_projects
    end
  end

  private

  def fetch_installations_on_schedule
    # Fetch jobs from today through the end of next week
    start_time = Time.now.beginning_of_day
    end_time = (Time.now + 1.week).end_of_week

    installation_jobs = SkeduloApi.find_jobs("Installation", start_time: start_time, end_time: end_time)
    powerwall_jobs = SkeduloApi.find_jobs("Tesla Powerwall", start_time: start_time, end_time: end_time)

    installation_jobs + powerwall_jobs
  end

  def fetch_scheduled_projects(jobs)
    # Build mapping of project_id to job start date
    job_start_by_project = {}
    jobs.each do |job|
      project_id = job.dig("node", "ProjectSunriseID")
      next unless project_id

      start_date = job.dig("node", "Start")
      if start_date && (!job_start_by_project[project_id] || start_date < job_start_by_project[project_id])
        job_start_by_project[project_id] = start_date
      end
    end

    project_ids = jobs.map { |job| job["node"]["ProjectSunriseID"] }.compact.uniq
    return [] if project_ids.empty?

    fields = [
      "fields.lender",
      "fields.lightreach_direct_pay",
      "fields.lightreach_direct_pay_po_link",
      "name",
      "fields.loan_application_id",
      "fields.market_region",
      "fields.system_size"
    ]

    result = ProjectSunriseApi.get_projects_bulk(project_ids, fields: fields)
    projects = result["items"] || []

    # Add job start date to each project (all scheduled installs are returned;
    # program classification happens downstream via ProgramType).
    projects.each do |project|
      project["job_start"] = job_start_by_project[project["_id"]]
    end

    projects
  end

  def batch_fetch_project_locations(project_ids)
    return {} if project_ids.empty?

    location_map = {}
    Rails.logger.info "[JobScheduleService] Fetching locations for #{project_ids.length} projects in batch"

    begin
      # Build SuiteQL query to fetch sales orders with locations
      # Location field is on TransactionLine table, accessed via JOIN
      external_ids = project_ids.map { |id| "'sales_order_#{id}'" }.join(", ")

      sql_query = <<-SQL
        SELECT t.externalid, tl.location
        FROM transaction t
        INNER JOIN transactionline tl ON t.id = tl.transaction
        WHERE t.externalid IN (#{external_ids})
          AND tl.mainline = 'T'
          AND t.type = 'SalesOrd'
      SQL

      Rails.logger.info "[JobScheduleService] SuiteQL query: #{sql_query.gsub(/\s+/, ' ').strip}"

      client = Netsuite::Client.new
      result = client.suiteql(query: sql_query)

      sales_orders = result["items"] || []
      Rails.logger.info "[JobScheduleService] Found #{sales_orders.length} sales orders from NetSuite"

      # Build location map from results
      sales_orders.each do |so|
        external_id = so["externalid"]
        Rails.logger.info "[JobScheduleService] Processing SO: externalId=#{external_id.inspect}, location=#{so['location'].inspect}"
        next unless external_id&.start_with?("sales_order_")

        project_id = external_id.sub("sales_order_", "")
        location_id = so["location"]
        location_map[project_id] = location_name_for(location_id)
      end

      # Fill in nil for any projects that weren't found
      project_ids.each do |project_id|
        unless location_map.key?(project_id)
          Rails.logger.warn "[JobScheduleService] No sales order found for project #{project_id}"
          location_map[project_id] = nil
        end
      end

      Rails.logger.info "[JobScheduleService] Successfully fetched locations for #{location_map.compact.length}/#{project_ids.length} projects"
    rescue StandardError => e
      Rails.logger.error "[JobScheduleService] Error batch fetching sales orders: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Fallback: set all to nil
      project_ids.each { |id| location_map[id] = nil }
    end

    location_map
  end

  def fetch_sales_order_id(project_id)
    # Use NetSuite external ID lookup directly (more reliable than HubSpot)
    external_id = "sales_order_#{project_id}"
    sales_order = Netsuite::SalesOrder.find_external(external_id)
    sales_order["id"]&.to_i
  rescue StandardError => e
    Rails.logger.error "Error fetching sales order ID for project #{project_id}: #{e.message}"
    nil
  end

  def fetch_sales_order_data(project_id)
    sales_order_id = fetch_sales_order_id(project_id)
    return nil unless sales_order_id

    sales_order = Netsuite::SalesOrder.find(sales_order_id)
    return nil unless sales_order

    {
      sales_order_id: sales_order_id,
      customer_id: sales_order.dig("entity", "id"),
      internal_project_id: sales_order.dig("job", "id"),
      location_id: sales_order.dig("location", "id"),
      ship_to_address: sales_order["shipAddress"],
      so_items: sales_order.dig("item", "items") || []
    }
  end

  def location_name_for(location_id)
    {
      1 => "Austin",
      2 => "Houston",
      3 => "Dallas",
      4 => "Austin",
      5 => "Denver",
      6 => "Co Springs",
      7 => "Tampa",
      17 => "Norfolk",
      18 => "Orlando",
      19 => "Charlotte",
      20 => "Raleigh",
      25 => "HQ",
      28 => "Commercial"
    }[location_id&.to_i] || "Location #{location_id}"
  end
end
