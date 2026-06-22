class EmailNotificationService
  def initialize(po_generation_job)
    @job = po_generation_job
    @po_generation_service = PoGenerationService.new(@job)
  end

  def send_batch_email(test_mode: false)
    return unless @job.completed?

    po_results = (@job.po_results || []).map(&:with_indifferent_access)
    return if po_results.empty?

    # Fetch individual PO PDFs from NetSuite and upload to Lightreach
    po_pdfs_by_id = {}
    po_results.each do |po_data|
      pdf_binary = Netsuite::PurchaseOrder.fetch_pdf_binary(po_data[:po_id])
      Rails.logger.info "Fetched PDF for PO #{po_data[:po_id]}, size: #{pdf_binary.bytesize} bytes"

      # Upload to Lightreach if account_id is available (skip in test mode)
      @po_generation_service.upload_po_to_lightreach(po_data, pdf_binary) if po_data[:lightreach_account_id].present? && !test_mode

      po_pdfs_by_id[po_data[:po_id]] = {
        po_id: po_data[:po_id],
        project_id: po_data[:project_id],
        pdf_binary: pdf_binary
      }
    end

    # Group POs by region (location_name) AND program so each email is branded for the
    # actual job type — a region batch can now contain mixed programs.
    pos_by_group = po_results.group_by { |po| [ po[:location_name], po[:program_key] ] }

    pos_by_group.each do |(region, program_key), group_pos|
      program = ProgramType.for_key(program_key)
      group_po_pdfs = group_pos.map { |po| po_pdfs_by_id[po[:po_id]] }
      group_summary_pdf = @po_generation_service.generate_location_summary_pdf(group_pos, region, program)

      PoMailer.regional_pos_created(
        region: region,
        created_pos: group_pos,
        po_pdfs: group_po_pdfs,
        summary_pdf: group_summary_pdf,
        program: program,
        test_mode: test_mode
      ).send_google

      Rails.logger.info "Sent #{program[:label]} PO email for region #{region} with #{group_pos.length} projects"
    end

    Rails.logger.info "Sent #{pos_by_group.keys.length} regional PO emails for #{po_results.length} total projects"
  rescue StandardError => e
    Rails.logger.error "Failed to send batch PO email: #{e.message}"
    raise
  end

  def send_single_email(po_result, cc_email: nil)
    pdf_binary = Netsuite::PurchaseOrder.fetch_pdf_binary(po_result[:po_id])
    Rails.logger.info "Fetched PDF for PO #{po_result[:po_id]}, size: #{pdf_binary.bytesize} bytes"

    # Upload to Lightreach if applicable
    @po_generation_service.upload_po_to_lightreach(po_result, pdf_binary) if po_result[:lightreach_account_id].present?

    # Send email with CC
    PoMailer.single_po_created(
      po_data: po_result,
      pdf_binary: pdf_binary,
      cc_email: cc_email
    ).send_google

    Rails.logger.info "Sent single PO email for project #{po_result[:project_id]}"
  rescue StandardError => e
    Rails.logger.error "Failed to send single PO email: #{e.message}"
    raise
  end
end
