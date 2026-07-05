Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions" }

  # Waitlist routes (pre-launch, accessible without authentication)
  get "waitlist", to: "waitlists#new", as: :new_waitlist
  post "waitlist", to: "waitlists#create", as: :waitlist
  get "waitlist/success", to: "waitlists#success", as: :waitlist_success

  # User invitation routes (outside dashboard, accessible without authentication)
  get "invitations/:token/accept", to: "user_invitations#show", as: :accept_invitation
  post "invitations/:token/accept", to: "user_invitations#accept", as: :submit_invitation

  # Trust Center (public compliance page, accessible without authentication)
  get "trust/:company_id", to: "trust_center#show", as: :trust_center

  get "standards/index"
  get "dashboard/index"
  get "home/index"

  # Dashboard routes
  get "dashboard", to: "dashboard#index"
  namespace :dashboard do
    # Overview Dashboard (Super Admin only)
    get "overview", to: "overview#index", as: :overview
    get "overview/avg_compliance", to: "overview#avg_compliance", as: :overview_avg_compliance
    get "overview/standards_compliance", to: "overview#standards_compliance", as: :overview_standards_compliance

    # Quality Manager Dashboard
    get "quality_manager", to: "quality_manager#index", as: :quality_manager

    get "ai_insights", to: "ai_insights#show", as: :ai_insights
    scope :capa_management, controller: :capa_management do
      get "/", action: :overview, as: :capa_management
      post "/", action: :create
      get "/export", action: :export, as: :export_capas
      get "/list", action: :list, as: :capa_management_list
      get "/board", action: :board, as: :capa_management_board
      get "/archives", action: :archives, as: :capa_management_archives
      get "/select_company", action: :select_company, as: :select_company_capa_management
      post "/set_company", action: :set_company, as: :set_company_capa_management
      get "/:id", action: :show, as: :capa_management_show
      delete "/:id", action: :destroy, as: :destroy_capa
      patch "/:id/status", action: :update_status, as: :update_capa_status
      post "/:id/regenerate_questionnaire", action: :regenerate_questionnaire, as: :regenerate_capa_questionnaire
      post "/:id/questionnaire/start", action: :start_questionnaire_generation, as: :start_questionnaire_generation
      post "/:id/questionnaire/generate_pair", action: :generate_question_pair, as: :generate_question_pair
      post "/:id/questionnaire/accept_pair", action: :accept_question_pair, as: :accept_question_pair
      post "/:id/questionnaire/regenerate_pair", action: :regenerate_question_pair, as: :regenerate_question_pair
      post "/:id/questionnaire/regenerate_root_cause", action: :regenerate_root_cause, as: :regenerate_root_cause
      post "/:id/questionnaire", action: :create_questionnaire, as: :create_capa_questionnaire
      patch "/:id/questionnaire", action: :update_questionnaire, as: :update_capa_questionnaire
      post "/:id/generate_actions", action: :generate_actions, as: :generate_capa_actions
      post "/:id/suggest_clauses", action: :suggest_clauses, as: :suggest_capa_clauses
      post "/:id/archive", action: :archive, as: :archive_capa
      post "/:id/unarchive", action: :unarchive, as: :unarchive_capa
      post "/bulk_archive", action: :bulk_archive, as: :bulk_archive_capas
      post "/bulk_unarchive", action: :bulk_unarchive, as: :bulk_unarchive_capas
      post "/bulk_delete", action: :bulk_delete, as: :bulk_delete_capas
      patch "/:id", action: :update, as: :update_capa
      get "/:capa_id/capa_actions/:id", action: :show_capa_action, as: :capa_action_show
      post "/:capa_id/capa_actions", action: :create_capa_action, as: :create_capa_action
      patch "/:capa_id/capa_actions/:id", action: :update_capa_action, as: :update_capa_action
      delete "/:capa_id/capa_actions/:id", action: :destroy_capa_action, as: :destroy_capa_action
      post "/:capa_id/capa_actions/:id/link_documents", action: :link_capa_action_documents, as: :link_capa_action_documents
      delete "/:capa_id/capa_actions/:id/unlink_document/:upload_id", action: :unlink_capa_action_document, as: :unlink_capa_action_document
      post "/:capa_id/capa_actions/:id/comments", action: :create_capa_action_comment, as: :create_capa_action_comment
      delete "/:capa_id/capa_actions/:id/comments/:comment_id", action: :destroy_capa_action_comment, as: :destroy_capa_action_comment
      post "/:capa_id/link_clauses", action: :link_clauses, as: :link_capa_clauses
      delete "/:capa_id/unlink_clause/:clause_id", action: :unlink_clause, as: :unlink_capa_clause
      post "/:capa_id/link_documents", action: :link_documents, as: :link_capa_documents
      delete "/:capa_id/unlink_document/:upload_id", action: :unlink_document, as: :unlink_capa_document
    end

    scope :risk_management, controller: :risk_management do
      get "/", action: :index, as: :risk_management_index
      post "/", action: :create
      get "/new", action: :new, as: :new_risk
      get "/:id", action: :show, as: :risk_management
      get "/:id/edit", action: :edit, as: :edit_risk
      patch "/:id", action: :update, as: :update_risk
      delete "/:id", action: :destroy, as: :destroy_risk
    end

    resources :risk_workspaces, only: [ :index, :new, :create, :show, :edit, :update, :destroy ]
    resources :customer_commitments, only: [ :index, :new, :create, :show, :edit, :update, :destroy ]
    resources :vendors, only: [ :index, :new, :create, :show, :edit, :update, :destroy ]
    resources :ai_instructions, only: [ :index, :new, :create, :edit, :update, :destroy ] do
      member { patch :toggle }
    end
    post "ai_assistant/ask", to: "ai_assistant#ask", as: :ai_assistant_ask

    resources :companies, only: [ :index ], controller: :companies

    # Account Management routes
    scope :account_management, controller: :account_management do
      get "/", action: :index, as: :account_management
      get "/users", action: :users, as: :account_management_users
      get "/companies", action: :companies, as: :account_management_companies
      get "/companies/:id", action: :company, as: :account_management_company
      post "/invitations", action: :create_invitation, as: :create_invitation
      post "/companies", action: :create_company, as: :create_company
      patch "/companies/:id/license_seats", action: :update_license_seats, as: :update_company_license_seats
      patch "/companies/:id/status", action: :update_company_status, as: :update_company_status
      patch "/companies/:id/trust_center", action: :toggle_trust_center, as: :toggle_company_trust_center
      patch "/users/:id/permissions", action: :update_permissions, as: :update_user_permissions
      patch "/users/:id/status", action: :update_user_status, as: :update_user_status
      patch "/users/:id/change_password", action: :change_password, as: :change_user_password
      patch "/users/:id/change_role", action: :change_role, as: :change_user_role
      delete "/users/:id", action: :destroy_user, as: :destroy_user
      delete "/companies/:id", action: :destroy_company, as: :destroy_company
    end

    # Notifications (full page + mark read)
    get "notifications", to: "notifications#index", as: :notifications
    get "notifications/:id/read_and_go", to: "notifications#read_and_go", as: :notification_read_and_go
    patch "notifications/mark_all_read", to: "notifications#mark_all_read", as: :notifications_mark_all_read
    patch "notifications/:id/read", to: "notifications#mark_read", as: :notification_mark_read

    # General settings routes
    get "general_settings", to: "general_settings#index", as: :general_settings
    patch "general_settings", to: "general_settings#update", as: :update_general_settings
    get "general_settings/export_analytics", to: "general_settings#export_analytics", as: :export_analytics, defaults: { format: :csv }
    resources :credit_changes, only: [ :index, :update ], controller: :credit_changes
    patch "credit_changes/company/:id", to: "credit_changes#update_company", as: :credit_changes_company
    get "credit_changes/company/:id/users", to: "credit_changes#company_users", as: :credit_changes_company_users
    post "credit_changes/company/:id/split_users", to: "credit_changes#split_company_credits", as: :credit_changes_company_split_users
    post "credit_changes/company/:id/reset_users", to: "credit_changes#reset_company_credits", as: :credit_changes_company_reset_users
    patch "credit_changes/company/:company_id/users/:id",
          to: "credit_changes#update_company_user",
          as: :credit_changes_company_user
    resources :credit_assignments, only: [ :update ], controller: :credit_assignments do
      collection do
        post :split_equally
        post :reset_assignments
      end
    end
  end
  get "standards", to: "standards#index"
  get "standards/compliance", to: "standards#standards_compliance", as: :standards_compliance
  get "clauses/:id/children", to: "standards#clause_children", as: :clause_children
  get "library", to: "library#index"
  get "library/folders/:id", to: "library#show", as: :folder, constraints: { id: /[^\/]+/ }
  post "library/folders", to: "library#create", as: :create_folder
  patch "library/folders/:id/color", to: "library#update_color", as: :update_folder_color
  patch "library/folders/:id/move", to: "library#move", as: :move_folder
  post "library/files/move", to: "library#move_file", as: :library_move_file

  # Upload routes - nested under folders (MUST come before folder delete route)
  get "uploads/new", to: "uploads#new", as: :new_upload
  post "uploads", to: "uploads#create", as: :uploads

  # Nested upload routes under folders
  scope "/library/folders/:folder_id", as: :folder_uploads do
    resources :uploads, only: [ :show, :update, :destroy ], path: "uploads" do
      member do
        get :download
        get :linked_items
        patch :update_visibility
      end
    end
  end

  # Folder delete route (MUST come after nested upload routes to avoid conflicts)
  delete "library/folders/:id", to: "library#destroy", as: :delete_folder

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Secured Ollama proxy (token in header). Deploy on server where Ollama runs; call from local with OLLAMA_PROXY_URL + OLLAMA_PROXY_TOKEN.
  match "ollama_proxy/*path", to: "ollama_proxy#forward", via: [ :get, :post ], format: false

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  root "home#index"

  post "standards/upload_standard", to: "standards#upload_standard"
  get "standards/:id/job_status", to: "standards#job_status", as: :standard_job_status
  get "standards/test_client", to: "standards#test_client"
  get "standards/test_tree", to: "standards#test_tree"
  get "standards/:id", to: "standards#show", as: :standard
  get "standards/:id/edit", to: "standards#edit", as: :edit_standard
  get "standards/:id/compare/:compare_with", to: "standards#compare", as: :compare_standard
  delete "standards/:id", to: "standards#destroy", as: :destroy_standard
  post "clauses", to: "standards#create_clause", as: :create_clause
  delete "clauses/:clause_id", to: "standards#destroy_clause", as: :destroy_clause
  post "checkpoints", to: "standards#create_checkpoint", as: :create_checkpoint
  delete "checkpoints/:checkpoint_id", to: "standards#destroy_checkpoint", as: :destroy_checkpoint
  patch "checkpoints/:checkpoint_id/mark_reviewed", to: "standards#mark_checkpoint_reviewed", as: :mark_checkpoint_reviewed
  patch "checkpoints/:checkpoint_id/move", to: "standards#move_checkpoint", as: :move_checkpoint
  patch "checkpoints/:checkpoint_id", to: "standards#update_checkpoint", as: :update_checkpoint
  patch "clauses/:clause_id/mark_reviewed", to: "standards#mark_clause_reviewed", as: :mark_clause_reviewed
  patch "clauses/:clause_id/move", to: "standards#move_clause", as: :move_clause
  patch "clauses/:clause_id/reorder", to: "standards#reorder_clause", as: :reorder_clause
  patch "clauses/:clause_id", to: "standards#update_clause", as: :update_clause
  patch "clauses/:clause_id/points", to: "standards#update_clause_points", as: :update_clause_points
  patch "clauses/:parent_id/distribute_weights", to: "standards#distribute_weights", as: :distribute_clause_weights
  patch "clauses/:parent_id/rollup_weights", to: "standards#rollup_weights", as: :rollup_clause_weights
  get "standards/:id/new_version", to: "standards#new_version", as: :new_version_standard
  post "standards/:id/new_version", to: "standards#create_version"
  patch "standards/:id/publish_version", to: "standards#publish_version", as: :publish_version_standard

  # API routes
  namespace :api do
    resources :versions, only: [] do
      get :clauses, on: :member
    end
    resources :standards, only: [] do
      get :terminal_clauses, on: :member
    end
    get "documents", to: "documents#index", defaults: { format: :json }, as: :documents
    get "folders", to: "folders#index", defaults: { format: :json }, as: :folders
    get "folders/:id", to: "folders#show", defaults: { format: :json }, as: :folder
  end

  # Standard versions API
  get "standards/:id/versions", to: "standards#versions", defaults: { format: :json }, as: :standard_versions
  get "standards/:id/versions/:version_id/available_companies", to: "standards#available_companies", defaults: { format: :json }, as: :available_companies
  post "standards/:id/assign", to: "standards#assign", as: :assign_standard

  # Evidence attachments routes
  resources :evidence_attachments, only: [ :create, :destroy ]

  # Language switching
  get "language/:locale", to: "application#switch_language", as: :switch_language

  # Sidekiq web interface (only in development)
  require "sidekiq/web"
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?

  # Search routes
  get "search", to: "search#index", as: :search
  get "api/search", to: "search#index", defaults: { format: :json }, as: :api_search
  get "api/search/clauses", to: "search#clauses", defaults: { format: :json }, as: :api_search_clauses



  # Mockup pages (no functionality, for client review)
  get "mockups/tool_builder", to: "mockups#tool_builder", as: :mockup_tool_builder
  get "mockups/evaluating_journey", to: "mockups#evaluating_journey", as: :mockup_evaluating_journey

  resources :tools, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
    member do
      post :link_standard
      delete :unlink_standard
      patch :mark_reviewed
    end
    collection do
      post :assign_multiple_users_to_subcheckpoint
      get :get_assignments
      post "switch_clause_tool", to: "tools#switch_clause_tool", as: :switch_clause_tool
      delete "unlink_clause_tool", to: "tools#unlink_clause_tool", as: :unlink_clause_tool
      delete :bulk_destroy
    end
  end
  patch "tool_checkpoints/:checkpoint_id/mark_reviewed", to: "tools#mark_checkpoint_reviewed", as: :mark_tool_checkpoint_reviewed
  patch "tool_subcheckpoints/:subcheckpoint_id/mark_reviewed", to: "tools#mark_subcheckpoint_reviewed", as: :mark_tool_subcheckpoint_reviewed

  # Terminal clause assessment page
  get "clauses/:clause_id/assessment", to: "assessments#show", as: :clause_assessment
  patch "clauses/:clause_id/assessment", to: "assessments#update", as: :update_clause_assessment
  post "clauses/:clause_id/assessment/assign_auditor", to: "assessments#assign_auditor", as: :assign_assessment_auditor
  post "clauses/:clause_id/assessment/comment", to: "assessments#add_comment", as: :comment_clause_assessment
  patch "clauses/:clause_id/assessment/autosave", to: "assessments#autosave", as: :autosave_clause_assessment

  # Legacy assignments URL — show redirects to /clauses/:id/assessment.
  # link_documents / unlink_document remain in active use by the new assessment view (JSON).
  get "assignments/:id", to: "assignments#show", as: :assignment
  post "assignments/:id/link_documents", to: "assignments#link_documents", as: :link_assignment_documents
  delete "assignments/:id/unlink_document/:upload_id", to: "assignments#unlink_document", as: :unlink_assignment_document
end
