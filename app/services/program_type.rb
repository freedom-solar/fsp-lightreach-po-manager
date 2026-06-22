# Classifies a Sunrise project into the PO program it belongs to and centralizes
# every program-specific value (vendor, PO naming, pricing, email/PDF branding) so
# the rest of the app never has to branch on the lender field directly.
#
# Classification is currently binary: "Lightreach Lease" projects are Direct Pay,
# everything else is a CED Kitted Job.
module ProgramType
  DIRECT_PAY = {
    key: :direct_pay,
    vendor_id: 2_660_586,
    vendor_name: "CED - Direct Pay",
    po_name_suffix: "Lightreach CED Direct Pay",
    label: "Lightreach Direct Pay",
    filename_slug: "Lightreach_Direct_Pay",
    zero_priced: true
  }.freeze

  CED_KITTED = {
    key: :ced_kitted,
    vendor_id: 1054,
    vendor_name: "CED",
    po_name_suffix: "CED Kitted Job",
    label: "CED Kitted Job",
    filename_slug: "CED_Kitted_Job",
    zero_priced: false
  }.freeze

  ALL = [ DIRECT_PAY, CED_KITTED ].freeze

  module_function

  # Returns the program entry for a Sunrise project hash.
  def for(project)
    direct_pay?(project) ? DIRECT_PAY : CED_KITTED
  end

  # Returns the program entry for a stored program key (e.g. from a po_result hash).
  # Falls back to DIRECT_PAY for blank/unknown keys so legacy po_results that predate
  # the program_key field keep their original Lightreach Direct Pay branding.
  def for_key(key)
    ALL.find { |program| program[:key].to_s == key.to_s } || DIRECT_PAY
  end

  def direct_pay?(project)
    project.dig("fields", "lender") == "Lightreach Lease"
  end
end
