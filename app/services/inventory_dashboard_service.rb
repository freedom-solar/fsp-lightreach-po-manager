# Builds the data for the Inventory dashboard (Warehouse Managers): open
# inventory-item purchase orders grouped by location -> project -> item, with
# what's not yet received, what's received-but-not-allocated, and late
# fulfillments measured against the Skedulo install schedule.
#
# All data is pulled live from NetSuite via SuiteQL plus a bulk Skedulo window
# fetch (no ETL); volumes are small and queries are tightly constrained.
#
# Join model (validated against production):
#   - PO line -> project via transactionline.entity; the project's number is
#     entity.entityid (e.g. "118811"), which is also the Skedulo ProjectSunriseID.
#   - Received qty = PO line quantityshiprecv.
#   - Allocated/fulfilled-to-job qty = the project's Sales Order line
#     quantityshiprecv (SO found by externalid = "sales_order_<project#>").
class InventoryDashboardService
  # Open PO statuses (not Fully Billed / Closed).
  OPEN_STATUS_CODES = %w[A B D E F].freeze

  PAGE_SIZE = 1000
  MAX_PAGES = 25

  # Skedulo schedule window and the "at-risk" horizon for late fulfillments.
  SCHEDULE_LOOKBACK_DAYS = 60
  SCHEDULE_LOOKAHEAD_DAYS = 14
  AT_RISK_DAYS = 7

  SKEDULO_INSTALL_TYPES = [ "Installation", "Tesla Powerwall" ].freeze

  def dashboard
    po_lines = fetch_open_po_lines
    project_numbers = po_lines.filter_map { |l| l[:project_number] }.uniq

    so_data = fetch_sales_order_data(project_numbers)
    schedule = fetch_schedule(project_numbers)

    rows = build_rows(po_lines, so_data, schedule)

    {
      generated_at: Time.current,
      count: rows.length,
      late_count: rows.count { |r| r[:late] },
      rows: rows
    }
  end

  private

  def client
    @client ||= Netsuite::Client.new
  end

  # --- NetSuite: open inventory PO lines -------------------------------------

  def fetch_open_po_lines
    run_suiteql(po_query).map { |row| normalize_po_line(row) }
  end

  def po_query
    <<~SQL.squish
      SELECT t.id AS po_id,
             t.tranid AS po_number,
             tl.item AS item_id,
             BUILTIN.DF(tl.item) AS item_name,
             BUILTIN.DF(tl.entity) AS project_name,
             BUILTIN.DF(tl.location) AS location,
             tl.quantity AS quantity,
             tl.quantityshiprecv AS quantity_received
      FROM transaction t
      INNER JOIN transactionline tl ON tl.transaction = t.id
      WHERE t.type = 'PurchOrd'
        AND t.status IN (#{quoted(OPEN_STATUS_CODES)})
        AND tl.mainline = 'F'
        AND tl.itemtype = 'InvtPart'
    SQL
  end

  def normalize_po_line(row)
    raw_project = row["project_name"].presence
    {
      po_id: row["po_id"],
      po_number: row["po_number"],
      item_id: row["item_id"],
      item: row["item_name"].presence || "Unknown Item",
      project_number: project_number_from(raw_project),
      project_name: clean_project_name(raw_project),
      location: row["location"].presence || "No Location",
      ordered: row["quantity"].to_f,
      received: row["quantity_received"].to_f
    }
  end

  # The SuiteQL REST role can't query the `entity` record, so the project number
  # is derived from the entity display name (BUILTIN.DF), whose leading token is
  # the entity id / project number, e.g. "118811 118811 - Iris Montero" -> "118811".
  def project_number_from(project_name)
    project_name&.strip&.split(/\s+/)&.first.presence
  end

  # BUILTIN.DF repeats the entity id in the display name, e.g.
  # "119417 119417 - Spencer Ashford"; drop the duplicated leading token.
  def clean_project_name(project_name)
    return "No Project" if project_name.blank?

    tokens = project_name.strip.split(/\s+/)
    tokens.shift if tokens.size >= 2 && tokens[0] == tokens[1]
    tokens.join(" ")
  end

  # --- NetSuite: allocated (fulfilled-to-job) quantities from Sales Orders ----

  # Returns { fulfilled: { [project_number, item_id] => qty }, so_ids: { project_number => so_id } }
  # by matching each project's Sales Order via externalid "sales_order_<project#>".
  def fetch_sales_order_data(project_numbers)
    fulfilled = Hash.new(0.0)
    so_ids = {}
    return { fulfilled: fulfilled, so_ids: so_ids } if project_numbers.empty?

    project_numbers.each_slice(200) do |slice|
      external_ids = slice.map { |n| "'sales_order_#{n}'" }.join(", ")
      run_suiteql(sales_order_query(external_ids)).each do |row|
        project_number = row["ext"].to_s.sub("sales_order_", "")
        fulfilled[[ project_number, row["item_id"] ]] += row["fulfilled"].to_f.abs
        so_ids[project_number] ||= row["so_id"]
      end
    end

    { fulfilled: fulfilled, so_ids: so_ids }
  end

  def sales_order_query(external_ids)
    <<~SQL.squish
      SELECT t.id AS so_id,
             t.externalid AS ext,
             tl.item AS item_id,
             tl.quantityshiprecv AS fulfilled
      FROM transaction t
      INNER JOIN transactionline tl ON tl.transaction = t.id
      WHERE t.type = 'SalesOrd'
        AND t.externalid IN (#{external_ids})
        AND tl.mainline = 'F'
        AND tl.itemtype = 'InvtPart'
    SQL
  end

  # --- Skedulo: scheduled install dates --------------------------------------

  # Returns { project_number => { date: Date, region: String } } for the
  # earliest scheduled install within the window.
  def fetch_schedule(project_numbers)
    return {} if project_numbers.empty?

    wanted = project_numbers.to_set
    # Use Time.now (system-local, carries a UTC offset) to match JobScheduleService:
    # SkeduloApi#format_time_to_skedulo mangles offset-less (UTC) timestamps.
    start_time = (Time.now - SCHEDULE_LOOKBACK_DAYS.days).beginning_of_day
    end_time = (Time.now + SCHEDULE_LOOKAHEAD_DAYS.days).end_of_day

    schedule = {}
    SKEDULO_INSTALL_TYPES.each do |type|
      SkeduloApi.find_jobs(type, start_time: start_time, end_time: end_time).each do |job|
        node = job["node"] || {}
        project_number = node["ProjectSunriseID"]
        start = node["Start"]
        next unless start && wanted.include?(project_number)

        current = schedule[project_number]
        next if current && current[:start_raw] <= start

        schedule[project_number] = {
          start_raw: start,
          date: parse_date(start),
          region: node.dig("Region", "Name")
        }
      end
    end

    schedule
  rescue StandardError => e
    Rails.logger.error("[InventoryDashboardService] Skedulo fetch failed: #{e.message}")
    {} # schedule is enrichment only; never block the dashboard on it
  end

  # --- Assembly --------------------------------------------------------------

  def build_rows(po_lines, so_data, schedule)
    fulfilled = so_data[:fulfilled]
    so_ids = so_data[:so_ids]
    grouped = po_lines.group_by { |l| [ l[:location], l[:project_number], l[:item_id] ] }

    rows = grouped.map do |(location, project_number, item_id), group|
      first = group.first
      ordered = group.sum { |l| l[:ordered] }
      received = group.sum { |l| l[:received] }
      allocated = fulfilled[[ project_number, item_id ]] || 0.0

      not_received = [ ordered - received, 0 ].max
      received_not_allocated = [ received - allocated, 0 ].max

      sched = project_number && schedule[project_number]
      urgency = schedule_urgency(sched)

      {
        location: location,
        project_number: project_number,
        project: first[:project_name],
        item: first[:item],
        po_numbers: group.map { |l| l[:po_number] }.uniq,
        po_links: group.uniq { |l| l[:po_id] }
                       .filter_map { |l| build_po_link(l) },
        so_link: netsuite_record_url("salesord", project_number && so_ids[project_number]),
        ordered_qty: ordered.round(2),
        received_qty: received.round(2),
        not_received_qty: not_received.round(2),
        received_not_allocated_qty: received_not_allocated.round(2),
        install_date: sched && sched[:date]&.iso8601,
        region: sched && sched[:region],
        urgency: urgency,
        late: !urgency.nil? && (not_received.positive? || received_not_allocated.positive?)
      }
    end

    # Only surface actionable rows (a receiving or allocation gap), late first.
    rows
      .select { |r| r[:not_received_qty].positive? || r[:received_not_allocated_qty].positive? }
      .sort_by { |r| [ urgency_rank(r[:urgency]), r[:location].to_s, r[:project].to_s, r[:item].to_s ] }
  end

  def schedule_urgency(sched)
    return nil unless sched && sched[:date]

    days_until = (sched[:date] - Date.current).to_i
    return "overdue" if days_until.negative?
    return "at_risk" if days_until <= AT_RISK_DAYS

    nil
  end

  def urgency_rank(urgency)
    { "overdue" => 0, "at_risk" => 1 }.fetch(urgency, 2)
  end

  # --- NetSuite deep links ---------------------------------------------------

  def build_po_link(line)
    url = netsuite_record_url("purchord", line[:po_id])
    return nil unless url

    { number: line[:po_number], url: url }
  end

  def netsuite_record_url(record_type, id)
    return nil if id.blank? || netsuite_base_url.blank?

    "#{netsuite_base_url}/app/accounting/transactions/#{record_type}.nl?id=#{id}"
  end

  def netsuite_base_url
    return @netsuite_base_url if defined?(@netsuite_base_url)

    account_id = Rails.application.credentials.dig(:netsuite, :production, :account_id_url)
    @netsuite_base_url = account_id.present? ? "https://#{account_id}.app.netsuite.com" : nil
  end

  # --- Helpers ---------------------------------------------------------------

  def run_suiteql(sql)
    items = []
    offset = 0

    MAX_PAGES.times do
      result = client.suiteql(query: sql, limit: PAGE_SIZE, offset: offset)

      # NetSuite returns an error body (no "items") on a bad query; surface it
      # instead of silently treating it as zero results.
      unless result.is_a?(Hash) && result.key?("items")
        raise "NetSuite SuiteQL error: #{result.inspect[0, 300]}"
      end

      items.concat(result["items"] || [])

      break unless result["hasMore"]

      offset += PAGE_SIZE
    end

    items
  end

  def quoted(codes)
    codes.map { |c| "'#{c}'" }.join(", ")
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError, TypeError
    nil
  end
end
