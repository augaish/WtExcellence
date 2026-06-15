class UserInvitationsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :show, :accept ]
  layout "application"

  def show
    @user = User.find_by(invitation_token: params[:token])

    unless @user
      redirect_to new_user_session_path, alert: "Invalid or expired invitation link."
      return
    end

    unless @user.invitation_valid?
      redirect_to new_user_session_path, alert: "This invitation link has expired. Please contact your administrator for a new invitation."
      nil
    end
  end

  def accept
    @user = User.find_by(invitation_token: params[:token])

    unless @user
      redirect_to new_user_session_path, alert: "Invalid or expired invitation link."
      return
    end

    unless @user.invitation_valid?
      redirect_to new_user_session_path, alert: "This invitation link has expired. Please contact your administrator for a new invitation."
      return
    end

    password = params[:password]
    password_confirmation = params[:password_confirmation]

    # Validate password
    if password.blank?
      flash.now[:alert] = "Password can't be blank."
      render :show, status: :unprocessable_entity
      return
    end

    if password != password_confirmation
      flash.now[:alert] = "Password confirmation doesn't match password."
      render :show, status: :unprocessable_entity
      return
    end

    if password.length < 8
      flash.now[:alert] = "Password is too short (minimum is 8 characters)."
      render :show, status: :unprocessable_entity
      return
    end

    # Update user password and accept invitation
    if @user.update(password: password, password_confirmation: password_confirmation)
      @user.accept_invitation!

      # Log invitation acceptance
      company = @user.company_user&.company
      if company
        AuditLogService.log_action(
          actor_user: @user,
          company: company,
          action: "ACCEPT_USER_INVITATION",
          entity_type: "user",
          entity_id: @user.id,
          payload: {
            user_name: @user.name,
            user_email: @user.email
          }
        )
      end

      redirect_to new_user_session_path, notice: "Password set successfully. Your account is pending activation by an administrator. You will be able to log in once your account has been activated."
    else
      flash.now[:alert] = @user.errors.full_messages.join(", ")
      render :show, status: :unprocessable_entity
    end
  end
end
