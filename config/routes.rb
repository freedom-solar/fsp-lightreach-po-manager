Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    sessions: "users/sessions"
  }

  devise_scope :user do
    get "users/sign_in", to: "users/sessions#new", as: :new_user_session
    get "users/sign_out", to: "users/sessions#destroy", as: :destroy_user_session
  end

  # Dashboard
  get "dashboard", to: "dashboard#index"

  # Link Hub - quick access to dashboards across the company
  get "link-hub", to: "dashboard#link_hub"

  # API routes (to be implemented)
  namespace :api do
    namespace :v1 do
      # Projects
      get "projects/schedule/:region", to: "projects#schedule_by_region"
      get "projects/:id", to: "projects#show"

      # PO Generation
      post "po_generation/region", to: "po_generation#generate_region"
      post "po_generation/project", to: "po_generation#generate_single"
      post "po_generation/batch", to: "po_generation#generate_batch"
      get "po_generation/jobs/:id", to: "po_generation#job_status"
      post "po_generation/cancel/:id", to: "po_generation#cancel"
      post "po_generation/resend_email", to: "po_generation#resend_email"

      # Material Return
      post "material_return/request", to: "material_return#create"

      # Procurement dashboard
      get "procurement/open_pos", to: "procurement#open_pos"

      # Inventory dashboard
      get "inventory/open_items", to: "inventory#open_items"
    end
  end

  # ActionCable
  mount ActionCable.server => "/cable"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Root path
  root "dashboard#index"
end
