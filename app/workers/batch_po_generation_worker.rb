class BatchPoGenerationWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'po_generation', retry: 0

  def perform(job_id)
    job = PoGenerationJob.find(job_id)

    job.update!(
      status: 'running',
      started_at: Time.current,
      locked_at: Time.current,
      locked_by: jid
    )

    service = PoGenerationService.new(job)
    service.log_progress("Starting PO generation for #{job.job_type} job")

    # Generate POs based on job type
    po_results = case job.job_type
                 when 'region'
                   service.generate_pos_for_region(job.region)
                 when 'single'
                   # For single project job
                   project_id = job.project_ids&.first
                   if project_id
                     result = service.generate_po_for_project(project_id)
                     result ? [result] : []
                   else
                     service.log_progress("No project ID provided for single job", level: :error)
                     []
                   end
                 when 'batch'
                   service.generate_pos_for_batch(job.project_ids)
                 else
                   service.log_progress("Unknown job type: #{job.job_type}", level: :error)
                   []
                 end

    # Update job with results
    job.update!(
      status: 'completed',
      successful_pos: po_results.length,
      failed_pos: job.total_projects - po_results.length,
      po_results: po_results,
      completed_at: Time.current
    )

    service.log_progress("Job completed: #{po_results.length} POs created successfully", level: :success)

    # Send batch email notification
    if po_results.any?
      service.log_progress("Sending email notifications...")
      EmailNotificationService.new(job).send_batch_email
    end

  rescue StandardError => e
    Rails.logger.error "BatchPoGenerationWorker failed for job #{job_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    if job && service
      service.log_progress("Job failed: #{e.message}", level: :error)
    end

    job.update!(
      status: 'failed',
      error_message: e.message,
      completed_at: Time.current
    ) if job
    raise
  ensure
    job.update!(locked_at: nil, locked_by: nil) if job&.persisted?
  end
end
