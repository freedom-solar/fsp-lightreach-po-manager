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

    # Check if job was cancelled before we started
    if job.reload.cancelled?
      service.log_progress("Job was cancelled before processing started", level: :warning)
      return
    end

    project_id = job.project_ids.first
    po_result = service.generate_po_for_project(project_id, skip_email: skip_email)

    if po_result
      # Check if job was cancelled during processing
      if job.reload.cancelled?
        service.log_progress("Job was cancelled during processing", level: :warning)
        return
      end

      job.update!(
        status: 'completed',
        successful_pos: 1,
        po_results: [po_result],
        completed_at: Time.current
      )

      # Broadcast status update to frontend via ActionCable
      ActionCable.server.broadcast(
        "po_generation_#{job.id}",
        {
          type: 'status_update',
          job_id: job.id,
          status: 'completed',
          total_projects: job.total_projects,
          successful_pos: 1,
          failed_pos: 0,
          completed_at: job.completed_at
        }
      )

      # Check if job was cancelled before sending email
      if job.reload.cancelled?
        service.log_progress("Job was cancelled before sending email", level: :warning)
        return
      end

      # Send email unless skipped
      unless skip_email
        service.log_progress("Sending email notification for PO #{po_result[:po_id]}")
        EmailNotificationService.new(job).send_single_email(po_result)
      end
    else
      job.update!(
        status: 'failed',
        failed_pos: 1,
        error_message: 'Failed to create PO',
        completed_at: Time.current
      )

      # Broadcast status update to frontend via ActionCable
      ActionCable.server.broadcast(
        "po_generation_#{job.id}",
        {
          type: 'status_update',
          job_id: job.id,
          status: 'failed',
          total_projects: job.total_projects,
          successful_pos: 0,
          failed_pos: 1,
          completed_at: job.completed_at
        }
      )
    end

  rescue StandardError => e
    job.update!(
      status: 'failed',
      error_message: e.message,
      completed_at: Time.current
    )

    # Broadcast status update to frontend via ActionCable
    ActionCable.server.broadcast(
      "po_generation_#{job.id}",
      {
        type: 'status_update',
        job_id: job.id,
        status: 'failed',
        total_projects: job.total_projects,
        successful_pos: job.successful_pos || 0,
        failed_pos: job.failed_pos || 1,
        completed_at: job.completed_at
      }
    )
    raise
  ensure
    job.update!(locked_at: nil, locked_by: nil) if job.persisted?
  end
end
