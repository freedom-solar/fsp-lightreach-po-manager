class PoGenerationWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'po_generation', retry: 0

  def perform(job_id, skip_email = false)
    job = PoGenerationJob.find(job_id)

    # Update status to running
    job.update!(
      status: 'running',
      started_at: Time.current,
      locked_at: Time.current,
      locked_by: jid
    )

    service = PoGenerationService.new(job)

    project_id = job.project_ids.first
    po_result = service.generate_po_for_project(project_id, skip_email: skip_email)

    if po_result
      job.update!(
        status: 'completed',
        successful_pos: 1,
        po_results: [po_result],
        completed_at: Time.current
      )

      # Send email unless skipped
      EmailNotificationService.new(job).send_batch_email unless skip_email
    else
      job.update!(
        status: 'failed',
        failed_pos: 1,
        error_message: 'Failed to create PO',
        completed_at: Time.current
      )
    end

  rescue StandardError => e
    job.update!(
      status: 'failed',
      error_message: e.message,
      completed_at: Time.current
    )
    raise
  ensure
    job.update!(locked_at: nil, locked_by: nil) if job.persisted?
  end
end
