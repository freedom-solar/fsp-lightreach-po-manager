module Api
  module V1
    class PoGenerationController < BaseController
      # POST /api/v1/po_generation/region
      # Generates POs for an entire region
      def generate_region
        region = params[:region]

        if region.blank?
          return render_error('Region parameter is required', status: :bad_request)
        end

        # Check if there's already a running job for this region
        if PoGenerationJob.running_for_region?(region)
          return render_error(
            "PO generation is already running for #{region}",
            status: :conflict
          )
        end

        # Create job record
        job = current_user.po_generation_jobs.create!(
          job_type: 'region',
          region: region,
          status: 'pending',
          total_projects: 0
        )

        # Enqueue worker
        BatchPoGenerationWorker.perform_async(job.id)

        render_success({
          job_id: job.id,
          region: region,
          status: 'pending',
          message: "PO generation started for #{region}"
        }, status: :created)
      rescue StandardError => e
        Rails.logger.error("Error starting region PO generation: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to start PO generation: #{e.message}", status: :internal_server_error)
      end

      # POST /api/v1/po_generation/project
      # Generates PO for a single project
      def generate_single
        project_id = params[:project_id]
        skip_email = params[:skip_email] == 'true' || params[:skip_email] == true
        skip_crew_check = params[:skip_crew_check] == 'true' || params[:skip_crew_check] == true

        if project_id.blank?
          return render_error('Project ID is required', status: :bad_request)
        end

        # Check if this project is already being processed
        locked_ids = PoGenerationJob.locked_project_ids
        if locked_ids.include?(project_id)
          return render_error(
            "PO generation is already running for project #{project_id}",
            status: :conflict
          )
        end

        # Create job record
        job = current_user.po_generation_jobs.create!(
          job_type: 'single',
          project_ids: [project_id],
          status: 'pending',
          total_projects: 1,
          skip_email: skip_email
        )

        # Enqueue worker
        PoGenerationWorker.perform_async(job.id, skip_email)

        render_success({
          job_id: job.id,
          project_id: project_id,
          status: 'pending',
          message: "PO generation started for project #{project_id}"
        }, status: :created)
      rescue StandardError => e
        Rails.logger.error("Error starting single project PO generation: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to start PO generation: #{e.message}", status: :internal_server_error)
      end

      # POST /api/v1/po_generation/batch
      # Generates POs for a batch of projects
      def generate_batch
        project_ids = params[:project_ids]

        if project_ids.blank? || !project_ids.is_a?(Array)
          return render_error('project_ids must be a non-empty array', status: :bad_request)
        end

        # Check if any projects are already being processed
        locked_ids = PoGenerationJob.locked_project_ids
        overlapping = project_ids & locked_ids

        if overlapping.any?
          render json: {
            success: false,
            error: "PO generation is already running for projects: #{overlapping.join(', ')}",
            data: {
              conflicting_projects: overlapping
            }
          }, status: :conflict
          return
        end

        # Create job record
        job = current_user.po_generation_jobs.create!(
          job_type: 'batch',
          project_ids: project_ids,
          status: 'pending',
          total_projects: project_ids.length
        )

        # Enqueue worker
        BatchPoGenerationWorker.perform_async(job.id)

        render_success({
          job_id: job.id,
          project_ids: project_ids,
          project_count: project_ids.length,
          status: 'pending',
          message: "PO generation started for #{project_ids.length} projects"
        }, status: :created)
      rescue StandardError => e
        Rails.logger.error("Error starting batch PO generation: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to start PO generation: #{e.message}", status: :internal_server_error)
      end

      # GET /api/v1/po_generation/jobs/:id
      # Gets the status and logs of a PO generation job
      def job_status
        job = PoGenerationJob.find(params[:id])

        # Get logs ordered by creation time
        logs = job.po_generation_logs.order(created_at: :asc).map do |log|
          {
            timestamp: log.created_at.strftime("%H:%M:%S"),
            level: log.level,
            message: log.message
          }
        end

        render_success({
          job: {
            id: job.id,
            job_type: job.job_type,
            region: job.region,
            project_ids: job.project_ids,
            status: job.status,
            total_projects: job.total_projects,
            successful_pos: job.successful_pos,
            failed_pos: job.failed_pos,
            error_message: job.error_message,
            started_at: job.started_at,
            completed_at: job.completed_at,
            created_at: job.created_at
          },
          logs: logs
        })
      rescue ActiveRecord::RecordNotFound
        render_error('Job not found', status: :not_found)
      rescue StandardError => e
        Rails.logger.error("Error fetching job status: #{e.message}")
        render_error("Failed to fetch job status: #{e.message}", status: :internal_server_error)
      end

      # POST /api/v1/po_generation/resend_email
      # Resends email for a completed PO generation job
      def resend_email
        job_id = params[:job_id]

        if job_id.blank?
          return render_error('Job ID is required', status: :bad_request)
        end

        job = PoGenerationJob.find(job_id)

        unless job.completed?
          return render_error('Can only resend emails for completed jobs', status: :bad_request)
        end

        if job.successful_pos.zero?
          return render_error('No successful POs to send', status: :bad_request)
        end

        # Send email
        EmailNotificationService.new(job).send_batch_email

        render_success({
          message: 'Email resent successfully',
          job_id: job.id
        })
      rescue ActiveRecord::RecordNotFound
        render_error('Job not found', status: :not_found)
      rescue StandardError => e
        Rails.logger.error("Error resending email: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to resend email: #{e.message}", status: :internal_server_error)
      end
    end
  end
end
