class MaterialReturnService
  def send_return_request(project_data:, message:, requester_email:)
    PoMailer.material_return_requested(
      project_data: project_data,
      return_message: message,
      requester_email: requester_email
    ).send_google

    Rails.logger.info "Sent material return request for project #{project_data[:project_id]}"
  end
end
