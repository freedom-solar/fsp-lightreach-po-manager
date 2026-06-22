module Api
  module V1
    class ProjectsController < BaseController
      # GET /api/v1/projects/schedule/:region
      def schedule_by_region
        region = params[:region]

        if region.blank?
          return render_error("Region parameter is required", status: :bad_request)
        end

        service = JobScheduleService.new
        projects = service.fetch_jobs_on_schedule(region: region)

        # Transform projects into frontend-friendly format
        formatted_projects = projects.map do |project|
          program = ProgramType.for(project)
          {
            id: project["_id"],
            name: project["name"],
            loan_application_id: project.dig("fields", "loan_application_id"),
            system_size: project.dig("fields", "system_size"),
            lender: project.dig("fields", "lender"),
            program_type: program[:key],
            program_label: program[:label],
            job_start: project["job_start"],
            po_link: project.dig("fields", "lightreach_direct_pay_po_link"),
            has_po: project.dig("fields", "lightreach_direct_pay_po_link").present?
          }
        end

        render_success({
          region: region,
          count: formatted_projects.length,
          projects: formatted_projects
        })
      rescue StandardError => e
        Rails.logger.error("Error fetching schedule for region #{region}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to fetch schedule: #{e.message}", status: :internal_server_error)
      end

      # GET /api/v1/projects/:id
      def show
        project_id = params[:id]

        fields = [
          "name",
          "fields.lightreach_direct_pay_po_link",
          "fields.loan_application_id",
          "fields.system_size",
          "fields.lender",
          "fields.market_region"
        ]

        result = ProjectSunriseApi.get_projects_bulk([ project_id ], fields: fields)
        project = result["items"]&.first

        unless project
          return render_error("Project not found", status: :not_found)
        end

        program = ProgramType.for(project)
        formatted_project = {
          id: project["_id"],
          name: project["name"],
          loan_application_id: project.dig("fields", "loan_application_id"),
          system_size: project.dig("fields", "system_size"),
          lender: project.dig("fields", "lender"),
          program_type: program[:key],
          program_label: program[:label],
          market_region: project.dig("fields", "market_region"),
          po_link: project.dig("fields", "lightreach_direct_pay_po_link"),
          has_po: project.dig("fields", "lightreach_direct_pay_po_link").present?
        }

        render_success({ project: formatted_project })
      rescue StandardError => e
        Rails.logger.error("Error fetching project #{project_id}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render_error("Failed to fetch project: #{e.message}", status: :internal_server_error)
      end
    end
  end
end
