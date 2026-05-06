class Lightreach::DirectPayMailer < ApplicationMailer
  default from: "project_sunrise@gofreedompower.com"

  FLORIDA_LOCATIONS = %w[Tampa Orlando].freeze
  TEXAS_LOCATIONS = [ "Austin", "Houston", "Dallas", "San Antonio" ].freeze

  def regional_pos_created(region:, created_pos:, po_pdfs:, summary_pdf:, test_mode: false)
    @region = region
    @created_pos = created_pos
    @total_projects = created_pos.length
    @generated_at = Time.now

    # Attach region summary PDF
    filename = "Lightreach_Direct_Pay_#{region.gsub(' ', '_')}_Summary.pdf"
    attachments[filename] = {
      mime_type: "application/pdf",
      content: summary_pdf
    }

    # Attach individual PO PDFs
    po_pdfs.each do |pdf_data|
      attachments["PO_#{pdf_data[:po_id]}_#{pdf_data[:project_id]}.pdf"] = {
        mime_type: "application/pdf",
        content: pdf_data[:pdf_binary]
      }
    end

    recipients = test_mode ? [ "dkimbriel@gofreedompower.com" ] : build_regional_recipient_list(region)
    subject_line = "Lightreach Direct Pay - #{region} - #{@total_projects} Purchase Orders Created"
    subject_line = "[TEST] #{subject_line}" if test_mode

    mail(
      to: recipients,
      subject: subject_line
    )
  end

  def single_po_created(po_data:, pdf_binary:, cc_email: nil)
    @po_data = po_data
    @generated_at = Time.now
    region = po_data[:location_name]

    attachments["PO_#{po_data[:po_id]}_#{po_data[:project_id]}.pdf"] = {
      mime_type: "application/pdf",
      content: pdf_binary
    }

    recipients = build_regional_recipient_list(region)
    mail_options = {
      to: recipients,
      subject: "Lightreach Direct Pay PO Created - Project #{po_data[:project_id]}"
    }
    mail_options[:cc] = cc_email if cc_email.present?

    mail(mail_options)
  end

  private

  def build_regional_recipient_list(region)
    recipients = [
      "dkimbriel@gofreedompower.com",
      "colby.clem@greentechrenewables.com",
      "jcarroll@gofreedompower.com",
      "dfisk@freedomsolarpower.com",
      "chad@freedomsolarpower.com"
    ] + DistributionList.warehouse

    # Add regional ROM instead of generic rom@
    regional_roms = DistributionList.regional_rom(region)
    recipients.concat(regional_roms) if regional_roms.present?

    # Add GreenTech regional contact
    if region == "Tampa"
      recipients << "hunter.david@greentechrenewables.com"
      recipients << "troy.walter@greentechrenewables.com"
    elsif region == "Orlando"
      recipients << "David.Principato@greentechrenewables.com"
      recipients << "jordan.swanson@greentechrenewables.com"
    elsif TEXAS_LOCATIONS.include?(region)
      recipients << "Sydni.landreneau@greentechrenewables.com"
      recipients << "alex.juarez@greentechrenewables.com"
    end

    recipients
  end
end
