class Dashboard::AccountManagementController < Dashboard::BaseController
  before_action :authenticate_user!
  before_action :ensure_super_admin_for_companies, only: [ :companies ]
  before_action :ensure_super_admin_for_permissions, only: [ :update_permissions ]

  def index
    # Overview page for Account Management
    @tab = "overview"

    # Filter by company for company admins
    if current_user&.company_user&.has_admin_privileges? && !current_user&.super_admin? && !current_user&.delegated_admin?
      company = current_company
      if company
        @total_companies = 1
        @total_users = company.company_users.count
        @active_users = company.company_users.joins(:user).where(users: { is_active: true }).count
        @inactive_users = @total_users - @active_users
        @total_credits = company.credits
        @recent_companies = [ company ]
      else
        @total_companies = 0
        @total_users = 0
        @active_users = 0
        @inactive_users = 0
        @total_credits = 0
        @recent_companies = []
      end
    else
      # Super admins and delegated admins see all data
      @total_companies      = Company.count
      @total_users          = User.count
      @active_users         = User.where(is_active: true).count
      @inactive_users       = @total_users - @active_users
      @total_credits        = Company.sum(:credits)
      @recent_companies = Company
        .includes(:company_users)
        .order(created_at: :desc)
        .limit(5)
    end
  end

  def users
    @tab = "users"

    # Filter by company for company admins
    if current_user&.company_user&.has_admin_privileges? && !current_user&.super_admin? && !current_user&.delegated_admin?
      company = current_company
      if company
        @users = User.joins(:company_user)
                     .where(company_users: { company_id: company.id })
                     .includes(:company_user, :company)
                     .order(created_at: :desc)
      else
        @users = User.none
      end
    else
      # Super admins and delegated admins see all users
      @users = User.includes(:company_user, :company)
                   .order(created_at: :desc)
    end

    # Apply filters
    @users = filter_users(@users)

    # Apply search
    @users = search_users(@users) if params[:search].present?

    # Apply sorting
    @users = sort_users(@users)

    # Paginate
    @pagy, @users = pagy(@users, items: 25)

    # Get unique roles for filter dropdown (filtered by company for company admins)
    @available_roles = get_available_roles
    @available_statuses = [ "active", "inactive" ]

    # Load data for invitation modal
    load_invitation_data
  end

  def company
    @tab = "company"

    @company = Company
      .includes(company_users: :user, uploads: :folder)
      .find(params[:id])

    # Only super admin and delegated admin can view any company; others only their own
    unless current_user&.super_admin? || current_user&.delegated_admin?
      unless current_company && @company.id == current_company.id
        redirect_to dashboard_account_management_path, alert: "You don't have permission to view this company."
        return
      end
    end

    @company_users   = @company.company_users.includes(:user)
    @recent_uploads  = @company.uploads.order(created_at: :desc).limit(10)

    # Load data for invitation modal (so super admin can add users from company profile)
    load_invitation_data
  end

  def companies
    @tab = "companies"
    @companies = Company.all

    # Apply filters
    @companies = filter_companies(@companies)

    # Apply search
    @companies = search_companies(@companies)

    # Apply sorting
    @companies = sort_companies(@companies)

    # Eager load associations after filtering/searching for better performance
    @companies = @companies.includes(:company_users)

    # Paginate
    @pagy, @companies = pagy(@companies, items: 25)

    # Load data for invitation modal
    load_invitation_data
  end

  def create_company
    unless current_user&.can_manage_companies?
      redirect_to dashboard_account_management_companies_path, alert: "You don't have permission to create companies."
      return
    end

    company = Company.new(company_params)
    company.is_active = true # New companies are active by default

    if company.save
      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: company,
        action: "CREATE_COMPANY",
        entity_type: "company",
        entity_id: company.id,
        payload: {
          company_id: company.id,
          company_name: company.name,
          license_seats: company.license_seats,
          credits: company.credits
        }
      )
      redirect_to dashboard_account_management_companies_path, notice: "Company '#{company.name}' created successfully."
    else
      redirect_to dashboard_account_management_companies_path, alert: "Failed to create company: #{company.errors.full_messages.join(', ')}"
    end
  end

  def update_permissions
    unless current_user&.super_admin?
      render json: { success: false, message: "Only Super Admins can update permissions." }, status: :forbidden
      return
    end

    user = User.find_by(id: params[:id])
    unless user
      render json: { success: false, message: "User not found." }, status: :not_found
      return
    end

    unless user.delegated_admin?
      render json: { success: false, message: "Permissions can only be updated for delegated admin users." }, status: :unprocessable_entity
      return
    end

    permissions = Array(params[:permissions] || []).map(&:to_s)

    previous_permissions = user.permissions_array.dup
    if user.update(permissions: permissions)
      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: user.company_user&.company || current_company,
        action: "UPDATE_USER_PERMISSIONS",
        entity_type: "user",
        entity_id: user.id,
        payload: {
          user_id: user.id,
          user_name: user.name,
          user_email: user.email,
          previous_permissions: previous_permissions,
          new_permissions: permissions
        }
      )
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Permissions updated successfully.", type: :success, animated: true }, formats: [ :html ])
      render json: {
        success: true,
        permissions: user.permissions_array,
        message: "Permissions updated successfully.",
        notification_html: notification_html
      }
    else
      notification_html = render_to_string(partial: "shared/notification", locals: { message: "Failed to update permissions: #{user.errors.full_messages.join(', ')}", type: :error, animated: true }, formats: [ :html ])
      render json: {
        success: false,
        message: user.errors.full_messages.join(", "),
        notification_html: notification_html
      }, status: :unprocessable_entity
    end
  end

  def update_license_seats
    unless current_user&.can_modify_license_seats?
      render json: { success: false, message: "You don't have permission to update license seats." }, status: :forbidden
      return
    end

    company = Company.find_by(id: params[:id])
    unless company
      render json: { success: false, message: "Company not found." }, status: :not_found
      return
    end

    license_seats = params[:license_seats]&.to_i
    if license_seats.nil? || license_seats < 0
      render json: { success: false, message: "License seats must be 0 or greater." }, status: :unprocessable_entity
      return
    end

    # Check if new license seats is less than current user count
    current_user_count = company.company_users.count
    if license_seats < current_user_count
      render json: { success: false, message: "Cannot reduce license seats below current user count (#{current_user_count} users)." }, status: :unprocessable_entity
      return
    end

    old_license_seats = company.license_seats
    if company.update(license_seats: license_seats)
      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: company,
        action: "UPDATE_COMPANY_LICENSE_SEATS",
        entity_type: "company",
        entity_id: company.id,
        payload: {
          company_id: company.id,
          company_name: company.name,
          old_license_seats: old_license_seats,
          new_license_seats: license_seats,
          current_user_count: company.company_users.count
        }
      )
      render json: { success: true, license_seats: company.license_seats, message: "License seats updated successfully." }
    else
      render json: { success: false, message: company.errors.full_messages.join(", ")       }, status: :unprocessable_entity
    end
  end

  def update_company_status
    unless current_user&.can_manage_companies?
      render json: { success: false, message: "You don't have permission to update company status." }, status: :forbidden
      return
    end

    company = Company.find_by(id: params[:id])
    unless company
      render json: { success: false, message: "Company not found." }, status: :not_found
      return
    end

    new_status = params[:status]
    unless %w[pending active].include?(new_status)
      render json: { success: false, message: "Invalid status. Must be 'pending' or 'active'." }, status: :unprocessable_entity
      return
    end

    old_status = company.status
    old_is_active = company.is_active?

    begin
      ActiveRecord::Base.transaction do
        # When activating a company, set both status and is_active
        if new_status == "active"
          company.status = "active"
          company.is_active = true

          # Activate all users in this company when company is activated
          company.users.update_all(is_active: true, status: "active")
        else
          company.status = "pending"
          company.is_active = false

          # Deactivate all users in this company when company is deactivated
          company.users.update_all(is_active: false)
        end

        unless company.save
          raise ActiveRecord::RecordInvalid.new(company)
        end

        # Log audit action
        activated_users_count = new_status == "active" ? company.users.count : 0
        deactivated_users_count = new_status == "pending" ? company.users.count : 0
        AuditLogService.log_action(
          actor_user: current_user,
          company: company,
          action: new_status == "active" ? "ACTIVATE_COMPANY" : "DEACTIVATE_COMPANY",
          entity_type: "company",
          entity_id: company.id,
          payload: {
            company_id: company.id,
            company_name: company.name,
          old_status: old_status,
          new_status: new_status,
          old_is_active: old_is_active,
          new_is_active: company.is_active,
          activated_users_count: activated_users_count,
          deactivated_users_count: deactivated_users_count
        }
      )

      message = if new_status == "active"
        "Company activated successfully. All users in this company have been activated."
      else
        "Company deactivated successfully. All users in this company have been deactivated."
      end

        render json: {
          success: true,
          status: company.status,
          is_active: company.is_active,
          message: message
        }
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: {
        success: false,
        message: e.record.errors.full_messages.join(", ")
      }, status: :unprocessable_entity
    end
  end

  def toggle_trust_center
    company = Company.find_by(id: params[:id])
    unless company
      render json: { success: false, message: "Company not found." }, status: :not_found
      return
    end

    allowed = current_user&.super_admin? || current_user&.delegated_admin? ||
      (current_user&.company_user&.has_admin_privileges? && current_company&.id == company.id)

    unless allowed
      render json: { success: false, message: "You don't have permission to update this company's Trust Center." }, status: :forbidden
      return
    end

    company.update!(trust_center_enabled: !company.trust_center_enabled)

    AuditLogService.log_action(
      actor_user: current_user,
      company: company,
      action: company.trust_center_enabled? ? "ENABLE_TRUST_CENTER" : "DISABLE_TRUST_CENTER",
      entity_type: "company",
      entity_id: company.id,
      payload: { company_id: company.id, trust_center_enabled: company.trust_center_enabled }
    )

    render json: {
      success: true,
      trust_center_enabled: company.trust_center_enabled,
      message: company.trust_center_enabled? ? "Trust Center enabled." : "Trust Center disabled."
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  # Toggle a per-company module on/off (super/delegated admins only).
  def toggle_module
    unless current_user&.super_admin? || current_user&.delegated_admin?
      render json: { success: false, message: "You don't have permission to change company modules." }, status: :forbidden
      return
    end

    company = Company.find_by(id: params[:id])
    unless company
      render json: { success: false, message: "Company not found." }, status: :not_found
      return
    end

    key = params[:module_key].to_s
    unless Company.module_keys.include?(key)
      render json: { success: false, message: "Unknown module." }, status: :unprocessable_entity
      return
    end

    new_state = !company.module_enabled?(key)
    company.set_module!(key, new_state)

    AuditLogService.log_action(
      actor_user: current_user,
      company: company,
      action: new_state ? "ENABLE_MODULE" : "DISABLE_MODULE",
      entity_type: "company",
      entity_id: company.id,
      payload: { company_id: company.id, module_key: key, enabled: new_state }
    )

    render json: { success: true, module_key: key, enabled: new_state }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  def change_password
    unless current_user&.super_admin?
      render json: { success: false, message: "Only Super Admins can change user passwords." }, status: :forbidden
      return
    end

    user = User.find_by(id: params[:id])
    unless user
      render json: { success: false, message: "User not found." }, status: :not_found
      return
    end

    if user.deleted?
      render json: { success: false, message: "Cannot change password for a deleted user." }, status: :unprocessable_entity
      return
    end

    password = params[:password]
    password_confirmation = params[:password_confirmation]

    if password.blank? || password_confirmation.blank?
      render json: { success: false, message: "Password and confirmation are required." }, status: :unprocessable_entity
      return
    end

    if password != password_confirmation
      render json: { success: false, message: "Password and confirmation do not match." }, status: :unprocessable_entity
      return
    end

    if password.length < 8
      render json: { success: false, message: "Password must be at least 8 characters long." }, status: :unprocessable_entity
      return
    end

    if user.update(password: password, password_confirmation: password_confirmation)
      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: user.company_user&.company || current_company,
        action: "CHANGE_USER_PASSWORD",
        entity_type: "user",
        entity_id: user.id,
        payload: {
          user_id: user.id,
          user_name: user.name,
          user_email: user.email,
          changed_by: current_user.name
        }
      )

      render json: {
        success: true,
        message: "Password changed successfully for #{user.name}."
      }
    else
      render json: {
        success: false,
        message: user.errors.full_messages.join(", ")
      }, status: :unprocessable_entity
    end
  end

  # The company admin names which quality managers run the Documenter flows.
  def toggle_pp_manager
    toggle_manager_flag(:pp_manager, requires: :company_quality_manager?, needs_key: "pp_manager_needs_qm")
  end

  # ... and which risk managers maintain the authority matrix.
  def toggle_gov_manager
    toggle_manager_flag(:gov_manager, requires: :company_risk_manager?, needs_key: "gov_manager_needs_rm")
  end

  def toggle_manager_flag(flag, requires:, needs_key:)
    membership = CompanyUser.find_by(user_id: params[:id], company_id: current_company&.id)
    unless current_user&.super_admin? || current_user&.company_user&.company_admin?
      return redirect_to dashboard_account_management_users_path, alert: t("documenter.flash.no_permission"), status: :see_other
    end
    return redirect_to dashboard_account_management_users_path, alert: t("user_not_found", default: "User not found."), status: :see_other if membership.nil?
    unless membership.public_send(requires)
      return redirect_to dashboard_account_management_users_path, alert: t("documenter.flash.#{needs_key}"), status: :see_other
    end

    membership.update!(flag => !membership.public_send(flag))
    AuditLogService.log_action(actor_user: current_user, company: membership.company, action: "TOGGLE_#{flag.to_s.upcase}",
      entity_type: "user", entity_id: membership.user_id, payload: { flag => membership.public_send(flag) })
    key = membership.public_send(flag) ? "#{flag}_set" : "#{flag}_unset"
    redirect_to dashboard_account_management_users_path, notice: t("documenter.flash.#{key}", name: membership.user.name), status: :see_other
  end

  def change_role
    unless current_user&.super_admin?
      render json: { success: false, message: "Only Super Admins can change user roles." }, status: :forbidden
      return
    end

    user = User.find_by(id: params[:id])
    unless user
      render json: { success: false, message: "User not found." }, status: :not_found
      return
    end

    if user.deleted?
      render json: { success: false, message: "Cannot change role for a deleted user." }, status: :unprocessable_entity
      return
    end

    new_global_role = params[:global_role]
    new_company_role = params[:company_role]

    # Validate global role
    valid_global_roles = [ "", "super_admin", "delegated_admin", "viewer" ]
    if new_global_role && !valid_global_roles.include?(new_global_role)
      render json: { success: false, message: "Invalid global role specified." }, status: :unprocessable_entity
      return
    end

    # Validate company role if provided
    if new_company_role
      valid_company_roles = CompanyUser::ROLES.values
      unless valid_company_roles.include?(new_company_role)
        render json: { success: false, message: "Invalid company role specified." }, status: :unprocessable_entity
        return
      end
    end

    # Prevent changing own role
    if user.id == current_user.id
      render json: { success: false, message: "You cannot change your own role." }, status: :unprocessable_entity
      return
    end

    previous_global_role = user.role
    previous_permissions = user.permissions_array.dup
    previous_company_role = user.company_user&.role

    # Update global role if provided
    if new_global_role
      if user.update(role: new_global_role.presence)
        # Clear permissions if not delegated_admin
        if new_global_role != "delegated_admin"
          user.update(permissions: [])
        end
      else
        render json: {
          success: false,
          message: user.errors.full_messages.join(", ")
        }, status: :unprocessable_entity
        return
      end
    end

    # Update company role if provided and user has company
    if new_company_role && user.company_user
      if user.company_user.update(role: new_company_role)
        # Success - both updates completed
      else
        render json: {
          success: false,
          message: user.company_user.errors.full_messages.join(", ")
        }, status: :unprocessable_entity
        return
      end
    end

    # Log audit action
    AuditLogService.log_action(
      actor_user: current_user,
      company: user.company_user&.company || current_company,
      action: "CHANGE_USER_ROLE",
      entity_type: "user",
      entity_id: user.id,
      payload: {
        user_id: user.id,
        user_name: user.name,
        user_email: user.email,
        previous_global_role: previous_global_role,
        new_global_role: new_global_role.presence || previous_global_role || "regular_user",
        previous_company_role: previous_company_role,
        new_company_role: new_company_role || previous_company_role,
        previous_permissions: previous_permissions,
        changed_by: current_user.name
      }
    )

    role_changes = []
    role_changes << "Global role: #{role_display_name(new_global_role || previous_global_role)}" if new_global_role
    role_changes << "Company role: #{company_role_display_name(new_company_role || previous_company_role)}" if new_company_role && user.company_user

    render json: {
      success: true,
      message: "Role changed successfully for #{user.name}. #{role_changes.join(', ')}",
      global_role: new_global_role.presence || previous_global_role || "regular_user",
      company_role: new_company_role || previous_company_role
    }
  end

  def update_user_status
    unless current_user&.can_activate_deactivate_users?
      redirect_back fallback_location: dashboard_account_management_users_path,
                    alert: "You don't have permission to update user status."
      return
    end

    user = User.find_by(id: params[:id])
    unless user
      redirect_back fallback_location: dashboard_account_management_users_path,
                    alert: "User not found."
      return
    end

    # Cannot activate a deleted user
    if user.deleted?
      redirect_back fallback_location: dashboard_account_management_users_path,
                    alert: "Cannot activate a deleted user."
      return
    end

    is_active_param = params[:is_active]
    if is_active_param.nil?
      redirect_back fallback_location: dashboard_account_management_users_path,
                    alert: "Invalid status parameter."
      return
    end

    new_status = ActiveModel::Type::Boolean.new.cast(is_active_param)

    # Prevent activating users if their company is pending
    if new_status == true
      user_company = user.company_user&.company
      if user_company&.status == "pending"
        redirect_back fallback_location: dashboard_account_management_users_path,
                      alert: "Cannot activate user: Company '#{user_company.name}' is pending. Please activate the company first."
        return
      end
    end

    old_status = user.is_active?
    if user.update(is_active: new_status)
      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: user.company_user&.company || current_company,
        action: new_status ? "ACTIVATE_USER" : "DEACTIVATE_USER",
        entity_type: "user",
        entity_id: user.id,
        payload: {
          user_id: user.id,
          user_name: user.name,
          user_email: user.email,
          old_status: old_status,
          new_status: new_status
        }
      )
      message_key = new_status ? "User has been activated." : "User has been deactivated."
      redirect_back fallback_location: dashboard_account_management_users_path,
                    notice: message_key
    else
      redirect_back fallback_location: dashboard_account_management_users_path,
                    alert: "Failed to update user status: #{user.errors.full_messages.join(', ')}"
    end
  end

  def role_display_name(role)
    case role
    when "super_admin"
      "Super Admin"
    when "delegated_admin"
      "Delegated Admin"
    when "viewer"
      "Viewer"
    else
      "Regular User"
    end
  end

  def company_role_display_name(role)
    return "None" unless role

    case role
    when "company_admin"
      "Company Admin"
    when "company_quality_manager"
      "Quality Manager"
    when "company_auditor"
      "Auditor"
    when "company_contributor"
      "Contributor"
    when "company_viewer"
      "Viewer"
    else
      role.gsub("company_", "").gsub("_", " ").split(" ").map(&:capitalize).join(" ")
    end
  end

  def create_invitation
    unless current_user&.can_add_users? || current_user&.company_user&.company_admin?
      redirect_to dashboard_account_management_users_path, alert: "You don't have permission to invite users."
      return
    end

    # Validate that only super admins can create delegated admins
    if params[:role] == "delegated_admin" && !current_user&.super_admin?
      redirect_to dashboard_account_management_users_path, alert: "Only Super Admins can create delegated admin users."
      return
    end

    # For delegated admins, company is optional
    is_delegated_admin = params[:role] == "delegated_admin"

    # Determine company (not required for delegated admins)
    company_id = if is_delegated_admin
      params[:company_id].presence # Optional for delegated admins
    elsif current_user&.platform_admin?
      params[:company_id]
    else
      current_user.company_user&.company_id
    end

    # Company is required for non-delegated admins
    unless is_delegated_admin || company_id.present?
      redirect_to dashboard_account_management_users_path, alert: "Company is required."
      return
    end

    company = nil
    if company_id.present?
      company = Company.find_by(id: company_id)
      unless company
        redirect_to dashboard_account_management_users_path, alert: "Invalid company."
        return
      end

      # Check license seats availability (only for company users)
      current_user_count = company.company_users.count
      if current_user_count >= company.license_seats
        redirect_to dashboard_account_management_users_path, alert: "Cannot invite user: Company has reached its license seat limit (#{company.license_seats} seats). Please upgrade the license or remove inactive users."
        return
      end
    end

    # Check if user already exists
    existing_user = User.find_by(email: params[:email])
    if existing_user
      if company && existing_user.company_user&.company_id == company.id
        redirect_to dashboard_account_management_users_path, alert: "User is already a member of this company."
        return
      end
      redirect_to dashboard_account_management_users_path, alert: "User with this email already exists."
      return
    end

    # Generate invitation token
    invitation_token = User.generate_invitation_token
    invitation_expires_at = 7.days.from_now

    # Generate a secure temporary password (user will set their own password when accepting invitation)
    temporary_password = SecureRandom.urlsafe_base64(32)

    # Set permissions for delegated admin
    permissions = []
    if is_delegated_admin && params[:permissions].present?
      permissions = Array(params[:permissions]).map(&:to_s)
    end

    # Determine if user should remain inactive due to pending company
    # Users in pending companies must stay inactive until company is activated
    is_company_pending = company&.status == "pending"

    # Create user with invitation
    user = User.new(
      name: params[:name],
      email: params[:email],
      role: params[:role].presence,
      permissions: permissions,
      password: temporary_password,
      password_confirmation: temporary_password,
      invitation_token: invitation_token,
      invitation_sent_at: Time.current,
      invitation_expires_at: invitation_expires_at,
      invited_by: current_user,
      is_active: false # User will be activated when they accept invitation (unless company is pending)
    )

    if user.save
      # Create company_user association only if company is provided
      if company.present?
        CompanyUser.create!(
          company: company,
          user: user,
          role: params[:company_role] || CompanyUser::ROLES[:company_contributor]
        )
      end

      # Send invitation email (company can be nil for delegated admins)
      # Use deliver_now in development for letter_opener, deliver_later in production
      if Rails.env.development?
        UserInvitationMailer.invitation_email(user, company).deliver_now
      else
        UserInvitationMailer.invitation_email(user, company).deliver_later
      end

      # Log audit action
      AuditLogService.log_action(
        actor_user: current_user,
        company: company || current_company,
        action: "CREATE_USER_INVITATION",
        entity_type: "user",
        entity_id: user.id,
        payload: {
          user_id: user.id,
          user_name: user.name,
          user_email: user.email,
          role: user.role,
          company_id: company&.id,
          company_name: company&.name,
          company_role: params[:company_role],
          permissions: permissions
        }
      )

      notice_message = if is_company_pending
        "Invitation sent successfully to #{user.email}. Note: User will remain inactive until company '#{company.name}' is activated."
      else
        "Invitation sent successfully to #{user.email}."
      end

      redirect_to dashboard_account_management_users_path, notice: notice_message
    else
      redirect_to dashboard_account_management_users_path, alert: "Failed to create invitation: #{user.errors.full_messages.join(', ')}"
    end
  end

  def destroy_user
    fallback = dashboard_account_management_users_path

    unless current_user&.super_admin?
      redirect_back fallback_location: fallback, alert: "Only Super Admins can delete user accounts.", status: :forbidden
      return
    end

    user = User.find_by(id: params[:id])
    unless user
      redirect_back fallback_location: fallback, alert: "User not found."
      return
    end

    if user.id == current_user.id
      redirect_back fallback_location: fallback, alert: "You cannot delete your own account."
      return
    end

    user_email = user.email
    user_name = user.name

    if UserDeletionService.call(user)
      redirect_back fallback_location: fallback, notice: "User '#{user_name}' (#{user_email}) has been permanently deleted. Any assigned credits have been returned to the company."
    else
      redirect_back fallback_location: fallback, alert: "Failed to delete user."
    end
  rescue UserDeletionService::CannotDeleteUserError => e
    redirect_back fallback_location: dashboard_account_management_users_path, alert: e.message
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_back fallback_location: dashboard_account_management_users_path, alert: "Could not delete user: #{e.message}"
  end

  def destroy_company
    fallback = dashboard_account_management_companies_path

    unless current_user&.can_remove_companies?
      redirect_back fallback_location: fallback, alert: "You don't have permission to remove companies."
      return
    end

    company = Company.find_by(id: params[:id])
    unless company
      redirect_back fallback_location: fallback, alert: "Company not found."
      return
    end

    company_name = company.name

    # Check if company has users
    if company.company_users.any?
      redirect_back fallback_location: fallback, alert: "Cannot delete company '#{company_name}': It has active users. Please remove all users first."
      return
    end

    # Remove audit logs that reference this company (FK would otherwise block destroy)
    AuditLog.where(company_id: company.id).delete_all

    if company.destroy
      redirect_to fallback, notice: "Company '#{company_name}' has been removed successfully."
    else
      redirect_back fallback_location: fallback, alert: "Failed to remove company: #{company.errors.full_messages.join(', ')}"
    end
  end

  # A pending invitation sent again with a fresh link, for a person whose
  # first email never arrived or expired.
  def resend_invitation
    unless current_user&.can_add_users? || current_user&.company_user&.company_admin?
      return redirect_to dashboard_account_management_users_path, alert: t("resend_invitation.not_permitted"), status: :see_other
    end

    user = User.find_by(id: params[:id])
    return redirect_to dashboard_account_management_users_path, alert: t("resend_invitation.not_found"), status: :see_other if user.nil? || !user.invited?

    own_company = current_user&.company_user&.company
    if !current_user&.can_add_users? && user.company_user&.company_id != own_company&.id
      return redirect_to dashboard_account_management_users_path, alert: t("resend_invitation.not_permitted"), status: :see_other
    end

    user.update!(invitation_token: User.generate_invitation_token, invitation_sent_at: Time.current,
      invitation_expires_at: 7.days.from_now, invited_by: current_user)
    company = user.company_user&.company
    mail = UserInvitationMailer.invitation_email(user, company)
    Rails.env.development? ? mail.deliver_now : mail.deliver_later
    AuditLogService.log_action(actor_user: current_user, company: company || current_company, action: "RESEND_USER_INVITATION",
      entity_type: "user", entity_id: user.id, payload: { user_id: user.id, user_name: user.name, user_email: user.email })

    redirect_back fallback_location: dashboard_account_management_users_path,
      notice: t("resend_invitation.sent", email: user.email), status: :see_other
  end

  # ---- Invite users from Excel (super admin and delegated admins who may add users) ----

  def import_users
    return unless load_import_company

    @template = UserImportTemplate.new(@company)
    @result = nil
  end

  def run_user_import
    return unless load_import_company

    @template = UserImportTemplate.new(@company)
    if params[:file].blank?
      @result = UserImportService::Result.new(invited: 0, errors: [ { row: 0, message: t("user_import.no_file") } ])
      return render :import_users, status: :unprocessable_entity
    end

    @result = UserImportService.import(file: params[:file], company: @company, actor: current_user)
    if @result.success?
      redirect_to dashboard_account_management_company_path(@company),
        notice: t("user_import.done", count: @result.invited, free: UserImportTemplate.new(@company).free_seats), status: :see_other
    else
      render :import_users, status: :unprocessable_entity
    end
  end

  def users_template
    return unless load_import_company

    send_data UserImportTemplate.new(@company).to_xlsx,
      filename: "users_template_#{@company.name.parameterize}.xlsx",
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  # The company whose users are imported. Only the platform side does this;
  # a company admin adds their people one at a time.
  def load_import_company
    unless current_user&.can_add_users?
      redirect_to dashboard_account_management_path, alert: t("user_import.not_permitted"), status: :see_other
      return false
    end

    @company = Company.find_by(id: params[:id])
    if @company.nil?
      redirect_to dashboard_account_management_companies_path, alert: t("user_import.no_company"), status: :see_other
      return false
    end
    true
  end

  def ensure_super_admin_for_companies
    unless current_user&.can_manage_companies?
      redirect_to dashboard_account_management_users_path, alert: "You don't have permission to access this page."
    end
  end

  def ensure_super_admin_for_permissions
    unless current_user&.super_admin?
      redirect_to dashboard_account_management_users_path, alert: "Only Super Admins can manage permissions."
    end
  end

  def filter_users(users)
    # Filter by role - can be either User role or CompanyUser role
    if params[:role].present?
      role_value = params[:role]
      # Check if it's a company role (starts with 'company_')
      if role_value.start_with?("company_")
        # Filter by CompanyUser role
        users = users.joins(:company_user).where(company_users: { role: role_value })
      else
        # Filter by User global role
        users = users.where(role: role_value)
      end
    end

    case params[:status]
    when "active"
      users = users.where(is_active: true)
    when "inactive"
      users = users.where(is_active: false)
    end

    users
  end

  def filter_companies(companies)
    # No filters applied for companies currently
    companies
  end

  def search_users(users)
    search_term = params[:search].to_s.downcase.strip
    return users if search_term.blank?

    users.left_joins(:company).where(
      "LOWER(users.name) LIKE ? OR LOWER(users.email) LIKE ? OR LOWER(companies.name) LIKE ?",
      "%#{search_term}%",
      "%#{search_term}%",
      "%#{search_term}%"
    )
  end

  def search_companies(companies)
    search_term = params[:search].to_s.downcase.strip
    return companies if search_term.blank?

    companies.where("LOWER(companies.name) LIKE ?", "%#{search_term}%")
  end

  def sort_users(users)
    case params[:sort]
    when "name_asc"
      users.order(name: :asc)
    when "name_desc"
      users.order(name: :desc)
    when "email_asc"
      users.order(email: :asc)
    when "email_desc"
      users.order(email: :desc)
    when "created_asc"
      users.order(created_at: :asc)
    when "created_desc"
      users.order(created_at: :desc)
    else
      users.order(created_at: :desc)
    end
  end

  def sort_companies(companies)
    case params[:sort]
    when "name_asc"
      companies.order(name: :asc)
    when "name_desc"
      companies.order(name: :desc)
    when "created_asc"
      companies.order(created_at: :asc)
    when "created_desc"
      companies.order(created_at: :desc)
    else
      companies.order(created_at: :desc)
    end
  end

  def get_available_roles
    roles = []

    # Filter by company for company admins
    if current_user&.company_user&.has_admin_privileges? && !current_user&.super_admin? && !current_user&.delegated_admin?
      company = current_company
      if company
        # Add User global roles for users in this company
        roles += User.joins(:company_user)
                     .where(company_users: { company_id: company.id })
                     .distinct.pluck(:role).compact
        # Add CompanyUser roles for this company
        roles += company.company_users.distinct.pluck(:role).compact
      end
    else
      # Super admins and delegated admins see all roles
      roles += User.distinct.pluck(:role).compact
      roles += CompanyUser.distinct.pluck(:role).compact
    end

    roles.uniq.sort
  end

  def get_user_status(user)
    user.is_active? ? "active" : "inactive"
  end

  def get_user_role_display(user)
    return "Super Admin" if user.super_admin?
    return "Delegated Admin" if user.delegated_admin?
    return user.company_user&.role&.gsub("company_", "")&.humanize || "User" if user.company_user
    "User"
  end

  def load_invitation_data
    # Load companies for invitation-related UI (separate from @companies used in listings)
    # Include pending companies so super admins can add users to them
    @invitation_companies = Company.all.order(:name) if current_user&.can_manage_companies?

    # Load company roles
    @company_roles = CompanyUser::ROLES.map { |key, value| [ key.to_s.humanize, value ] }
  end

  def company_params
    params.require(:company).permit(:name, :license_seats, :credits)
  end

  helper_method :get_user_status, :get_user_role_display
end
