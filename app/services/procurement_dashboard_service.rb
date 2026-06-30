# Builds the data for the Procurement dashboard: open Purchase Orders that
# contain "Contract Labor" lines, grouped by NetSuite Class + Location and
# pivoted by vendor, with pending-receipt and pending-bill flagged separately.
#
# Data is pulled live from NetSuite via SuiteQL (no ETL). The query is tightly
# constrained (transaction type + item + status) so it returns quickly;
# unconstrained aggregates over the transaction table time out.
class ProcurementDashboardService
  # Internal id of the "Contract Labor" non-inventory item in NetSuite.
  CONTRACT_LABOR_ITEM_ID = 325

  # Purchase Order statuses considered "open" (not Fully Billed / Closed).
  OPEN_STATUS_CODES = %w[A B D E F].freeze

  # NetSuite PO status code -> human label.
  STATUS_LABELS = {
    "A" => "Pending Supervisor Approval",
    "B" => "Pending Receipt",
    "D" => "Partially Received",
    "E" => "Pending Billing/Partially Received",
    "F" => "Pending Bill"
  }.freeze

  PAGE_SIZE = 1000
  MAX_PAGES = 25 # safety cap (25k lines) to avoid an unbounded loop

  # Returns a structured payload for the dashboard:
  #   {
  #     generated_at: Time,
  #     count: <number of PO rows>,
  #     total_unbilled_amount: <float>,
  #     rows: [ { po_number:, vendor:, ns_class:, location:, status_label:,
  #               ordered_qty:, received_qty:, billed_qty:, amount:,
  #               unbilled_amount:, pending_receipt:, pending_bill:,
  #               projects: [..] }, ... ]
  #   }
  def dashboard
    rows = aggregate_rows(fetch_open_lines)

    {
      generated_at: Time.current,
      count: rows.length,
      total_unbilled_amount: rows.sum { |r| r[:unbilled_amount] }.round(2),
      rows: rows
    }
  end

  private

  # Fetches and normalizes every open Contract Labor PO line from NetSuite.
  def fetch_open_lines
    client = Netsuite::Client.new
    lines = []
    offset = 0

    MAX_PAGES.times do
      result = client.suiteql(query: suiteql, limit: PAGE_SIZE, offset: offset)
      items = result["items"] || []
      lines.concat(items.map { |row| normalize_line(row) })

      break unless result["hasMore"]

      offset += PAGE_SIZE
    end

    lines
  end

  def suiteql
    <<~SQL.squish
      SELECT t.id AS po_id,
             t.tranid AS po_number,
             BUILTIN.DF(t.entity) AS vendor,
             t.status AS status_code,
             t.trandate AS po_date,
             BUILTIN.DF(tl.class) AS ns_class,
             BUILTIN.DF(tl.location) AS location,
             BUILTIN.DF(tl.entity) AS project,
             tl.quantity AS quantity,
             tl.quantityshiprecv AS quantity_received,
             tl.quantitybilled AS quantity_billed,
             tl.rate AS rate
      FROM transaction t
      INNER JOIN transactionline tl ON tl.transaction = t.id
      WHERE t.type = 'PurchOrd'
        AND tl.item = #{CONTRACT_LABOR_ITEM_ID}
        AND tl.mainline = 'F'
        AND t.status IN (#{OPEN_STATUS_CODES.map { |c| "'#{c}'" }.join(', ')})
    SQL
  end

  # Deep link to the Purchase Order record in the NetSuite UI. Returns nil if the
  # account id isn't configured so the frontend can fall back to plain text.
  def netsuite_po_url(po_id)
    return nil if po_id.blank? || netsuite_base_url.blank?

    "#{netsuite_base_url}/app/accounting/transactions/purchord.nl?id=#{po_id}"
  end

  def netsuite_base_url
    return @netsuite_base_url if defined?(@netsuite_base_url)

    account_id = Rails.application.credentials.dig(:netsuite, :production, :account_id_url)
    @netsuite_base_url = account_id.present? ? "https://#{account_id}.app.netsuite.com" : nil
  end

  # Days since the PO date, or nil if the date can't be parsed.
  def days_since(date_string)
    date = parse_date(date_string)
    return nil unless date

    (Date.current - date).to_i
  end

  # NetSuite SuiteQL returns dates like "6/22/2023"; fall back to a lenient parse.
  def parse_date(value)
    return nil if value.blank?

    Date.strptime(value, "%m/%d/%Y")
  rescue ArgumentError
    begin
      Date.parse(value)
    rescue ArgumentError, TypeError
      nil
    end
  end

  def normalize_line(row)
    ordered  = row["quantity"].to_f
    received = row["quantity_received"].to_f
    billed   = row["quantity_billed"].to_f
    rate     = row["rate"].to_f
    status   = row["status_code"]

    {
      po_id: row["po_id"],
      po_number: row["po_number"],
      po_date: row["po_date"],
      age_days: days_since(row["po_date"]),
      vendor: row["vendor"].presence || "Unknown Vendor",
      ns_class: row["ns_class"].presence || "Unclassified",
      location: row["location"].presence || "No Location",
      project: row["project"],
      status_code: status,
      status_label: STATUS_LABELS.fetch(status, status),
      ordered_qty: ordered,
      received_qty: received,
      billed_qty: billed,
      amount: (ordered * rate).round(2),
      unbilled_amount: ([ ordered - billed, 0 ].max * rate).round(2),
      pending_receipt: received < ordered,
      pending_bill: billed < ordered
    }
  end

  # Collapses lines into one row per PO + Class + Location (vendor is constant
  # per PO). Quantities/amounts are summed; pending flags are OR-ed across lines.
  def aggregate_rows(lines)
    grouped = lines.group_by { |l| [ l[:po_id], l[:ns_class], l[:location] ] }

    rows = grouped.map do |_key, group|
      first = group.first
      {
        po_number: first[:po_number],
        netsuite_url: netsuite_po_url(first[:po_id]),
        po_date: first[:po_date],
        age_days: first[:age_days],
        vendor: first[:vendor],
        ns_class: first[:ns_class],
        location: first[:location],
        status_label: first[:status_label],
        projects: group.filter_map { |l| l[:project] }.uniq,
        ordered_qty: group.sum { |l| l[:ordered_qty] }.round(2),
        received_qty: group.sum { |l| l[:received_qty] }.round(2),
        billed_qty: group.sum { |l| l[:billed_qty] }.round(2),
        amount: group.sum { |l| l[:amount] }.round(2),
        unbilled_amount: group.sum { |l| l[:unbilled_amount] }.round(2),
        pending_receipt: group.any? { |l| l[:pending_receipt] },
        pending_bill: group.any? { |l| l[:pending_bill] }
      }
    end

    rows.sort_by { |r| [ r[:ns_class], r[:location], r[:vendor], r[:po_number].to_s ] }
  end
end
