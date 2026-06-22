require "rails_helper"

RSpec.describe MaterialReturnService do
  let(:service) { described_class.new }
  let(:project_data) do
    {
      project_id: "SF-001",
      project_name: "Test Project",
      po_id: 12345,
      po_link: "https://netsuite.com?id=12345",
      region: "Austin",
      system_size: 10.5,
      po_items: [
        { description: "Solar Panel", quantity: 20 }
      ]
    }
  end
  let(:message) { "Customer cancelled installation" }
  let(:requester_email) { "user@gofreedompower.com" }

  describe "#send_return_request" do
    before do
      allow(DistributionList).to receive(:warehouse).and_return([ "warehouse@example.com" ])
      allow(DistributionList).to receive(:regional_rom).and_return([ "rom@example.com" ])
    end

    it "sends material return email" do
      expect(PoMailer).to receive(:material_return_requested)
        .with(
          project_data: project_data,
          return_message: message,
          requester_email: requester_email
        )
        .and_call_original

      service.send_return_request(
        project_data: project_data,
        message: message,
        requester_email: requester_email
      )
    end

    it "logs the request" do
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with(/Sent material return request for project SF-001/)

      service.send_return_request(
        project_data: project_data,
        message: message,
        requester_email: requester_email
      )
    end
  end
end
