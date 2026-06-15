class Users::SessionsController < Devise::SessionsController
  # POST /resource/sign_in
  def create
    super
    # Log successful login after sign in completes
    if user_signed_in? && current_user.present?
      # Get company from company_user, or use first active company for super admins/delegated admins
      company = current_user.company_user&.company
      if company.nil? && (current_user.super_admin? || current_user.delegated_admin?)
        company = Company.active.order(:created_at).first
      end

      if company
        AuditLogService.log_action(
          actor_user: current_user,
          company: company,
          action: "USER_LOGIN",
          entity_type: "user",
          entity_id: current_user.id,
          payload: {
            user_name: current_user.name,
            user_email: current_user.email
          }
        )
      end
    end
  end

  # POST /resource/sign_out
  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    set_flash_message! :notice, :signed_out if signed_out

    # Add custom flash message
    flash[:notice] = "You have been signed out successfully."

    yield if block_given?
    respond_to_on_destroy
  end

  protected

  def respond_to_on_destroy
    redirect_to after_sign_out_path_for(resource_name), status: :see_other
  end
end
