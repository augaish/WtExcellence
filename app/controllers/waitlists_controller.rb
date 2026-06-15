class WaitlistsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :new, :create, :success ]
  before_action :set_available_roles, only: [ :new, :create ]
  layout "application"

  def new
    # No authentication required
  end

  def create
    # Validate input
    unless validate_params
      flash.now[:alert] = @error_message
      render :new, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      # Find or create company (allows multiple people from same company to join waitlist)
      @company = Company.find_or_initialize_by(name: waitlist_params[:company_name]) do |company|
        company.company_size = waitlist_params[:company_size]
        company.status = "pending"
        company.is_active = false
        company.license_seats = 0
        company.credits = 0
      end

      # Update company_size if company already exists but size is different
      if @company.persisted? && @company.company_size != waitlist_params[:company_size]
        @company.company_size = waitlist_params[:company_size]
      end

      unless @company.save
        flash.now[:alert] = "Company could not be created: #{@company.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
        raise ActiveRecord::Rollback
        return
      end

      # Create user with pending status
      @user = User.new(
        name: waitlist_params[:name],
        email: waitlist_params[:email],
        desired_role: waitlist_params[:role],
        status: "pending",
        is_active: false,
        password: SecureRandom.hex(32) # Temporary password, will be changed later
      )

      unless @user.save
        flash.now[:alert] = "User could not be created: #{@user.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
        raise ActiveRecord::Rollback
        return
      end

      # Associate user to company
      company_user = CompanyUser.new(
        company: @company,
        user: @user,
        role: CompanyUser::ROLES[:company_admin] # Default to admin for waitlist
      )

      unless company_user.save
        flash.now[:alert] = "Association could not be created: #{company_user.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
        raise ActiveRecord::Rollback
        return
      end

      # Send welcome email
      begin
        # Get current locale from session or default
        current_locale = session[:locale] || I18n.locale
        WaitlistMailer.welcome_email(@user, @company, current_locale).deliver_later
      rescue => e
        Rails.logger.error "Failed to send waitlist email: #{e.message}"
        # Don't fail the registration if email fails
      end

      # Redirect to success page
      redirect_to waitlist_success_path
    end
  rescue => e
    Rails.logger.error "Waitlist creation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash.now[:alert] = "An error occurred. Please try again."
    render :new, status: :unprocessable_entity
  end

  def success
    # No authentication required
  end

  private

  def set_available_roles
    # Get all company roles (excluding super_admin and delegated_admin which are User-level roles)
    @available_roles = CompanyUser::ROLES.map { |key, value| [ key.to_s.humanize, value ] }
  end

  def waitlist_params
    params.permit(:name, :email, :company_name, :company_size, :role)
  end

  def validate_params
    # Check required fields
    if waitlist_params[:name].blank?
      @error_message = "Full name is required"
      return false
    end

    if waitlist_params[:email].blank?
      @error_message = "Email is required"
      return false
    end

    # Validate email format
    unless waitlist_params[:email].match?(/\A[^@\s]+@[^@\s]+\z/)
      @error_message = "Email is invalid"
      return false
    end

    if waitlist_params[:company_name].blank?
      @error_message = "Company name is required"
      return false
    end

    if waitlist_params[:company_size].blank?
      @error_message = "Company size is required"
      return false
    end

    if waitlist_params[:role].blank?
      @error_message = "Role is required"
      return false
    end

    # Check if email already exists
    if User.exists?(email: waitlist_params[:email])
      @error_message = "This email is already registered"
      return false
    end

    true
  end
end
