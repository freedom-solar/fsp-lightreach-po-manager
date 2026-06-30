# Builds the Missed Fulfillments report: Sales Orders that are Pending
# Fulfillment or Partially Fulfilled whose scheduled date is in the past.
#
# The governing date comes from the SO's own custom body fields (to match
# NetSuite reporting), not Skedulo:
#   - scheduled installation date: custbodycustbody_installation_date
#   - scheduled electrical date:   custbodyelectrical_date
# If the SO carries any Energy Storage Components item (item.custitem1 = 18),
# it isn't past due until the electrical date; otherwise the installation date.
class MissedFulfillmentService
  # Sales Order statuses that still have unfulfilled lines (excludes Pending
  # Billing, Billed, Closed, Cancelled).
  OPEN_STATUS_CODES = %w[B D].freeze

  STATUS_LABELS = {
    "B" => "Pending Fulfillment",
    "D" => "Partially Fulfilled"
  }.freeze

  # item.custitem1 (item category) value for "Energy Storage Components".
  ENERGY_STORAGE_CATEGORY_ID = 18

  PAGE_SIZE = 1000
  MAX_PAGES = 25

  def report
    headers = fetch_open_sales_orders
    line_meta = fetch_line_meta # so_id => { has_storage:, location_id: }

    rows = build_rows(headers, line_meta)

    {
      generated_at: Time.current,
      count: rows.length,
      rows: rows
    }
  end

  private

  def client
    @client ||= Netsuite::Client.new
  end

  # One row per open (B/D) Sales Order with its scheduled custom dates.
  def fetch_open_sales_orders
    run_suiteql(<<~SQL.squish)
      SELECT t.id AS so_id,
             t.tranid AS project_number,
             BUILTIN.DF(t.entity) AS customer,
             t.status AS status_code,
             t.custbodycustbody_installation_date AS install_date,
             t.custbodyelectrical_date AS electrical_date
      FROM transaction t
      WHERE t.type = 'SalesOrd'
        AND t.status IN (#{quoted(OPEN_STATUS_CODES)})
    SQL
  end

  # Per-SO: whether any line is an Energy Storage Components item, and a
  # representative location. Joins `item` (allowed in SuiteQL; `entity` is not).
  def fetch_line_meta
    meta = {}
    run_suiteql(<<~SQL.squish).each do |row|
      SELECT tl.transaction AS so_id,
             MAX(CASE WHEN i.custitem1 = #{ENERGY_STORAGE_CATEGORY_ID} THEN 1 ELSE 0 END) AS has_storage,
             MAX(tl.location) AS location_id
      FROM transaction t
      INNER JOIN transactionline tl ON tl.transaction = t.id
      INNER JOIN item i ON i.id = tl.item
      WHERE t.type = 'SalesOrd'
        AND t.status IN (#{quoted(OPEN_STATUS_CODES)})
        AND tl.mainline = 'F'
      GROUP BY tl.transaction
    SQL
      meta[row["so_id"]] = {
        has_storage: row["has_storage"].to_i == 1,
        location_id: row["location_id"]
      }
    end
    meta
  end

  def build_rows(headers, line_meta)
    rows = headers.filter_map do |h|
      meta = line_meta[h["so_id"]] || {}
      has_storage = meta[:has_storage]

      # Energy-storage SOs aren't past due until their electrical date — but only
      # when one is actually set; otherwise fall back to the installation date.
      use_electrical = has_storage && h["electrical_date"].present?
      governing_basis = use_electrical ? "electrical" : "installation"
      governing_date = parse_date(use_electrical ? h["electrical_date"] : h["install_date"])
      next unless governing_date && governing_date < Date.current

      {
        project_number: h["project_number"],
        customer: h["customer"],
        location: location_name(meta[:location_id]),
        status_label: STATUS_LABELS.fetch(h["status_code"], h["status_code"]),
        has_storage: has_storage,
        installation_date: parse_date(h["install_date"])&.iso8601,
        electrical_date: parse_date(h["electrical_date"])&.iso8601,
        governing_basis: governing_basis,
        days_overdue: (Date.current - governing_date).to_i,
        netsuite_url: netsuite_record_url("salesord", h["so_id"])
      }
    end

    rows.sort_by { |r| -r[:days_overdue] }
  end

  def location_name(location_id)
    return "No Location" if location_id.blank?

    location_names[location_id.to_s] || "No Location"
  end

  def location_names
    @location_names ||= run_suiteql("SELECT id, name FROM location")
                        .to_h { |r| [ r["id"].to_s, r["name"] ] }
  end

  # --- NetSuite deep links ---------------------------------------------------

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

  # NetSuite returns dates like "2/26/2026"; fall back to a lenient parse.
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
end
