class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    # Main dashboard view - React will take over from here
  end

  def link_hub
    # Link Hub - quick access to dashboards across the company
  end
end
