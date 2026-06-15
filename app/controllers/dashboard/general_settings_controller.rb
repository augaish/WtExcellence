class Dashboard::GeneralSettingsController < Dashboard::BaseController
  def index
  end

  def update
    return if prevent_viewer_action
    # Handle profile image removal
    if params[:user][:remove_profile_image] == "1"
      current_user.profile_image.purge if current_user.profile_image.attached?
    end

    # Only allow name updates for platform admins
    update_params = user_params
    unless current_user&.platform_admin?
      update_params = update_params.except(:name)
    end

    # Track name change for audit log
    old_name = current_user.name
    name_changed = update_params[:name].present? && update_params[:name] != old_name

    if current_user.update(update_params)
      # Log audit action for name changes (especially important for super admins)
      if name_changed
        AuditLogService.log_action(
          actor_user: current_user,
          company: current_user.company_user&.company || current_company,
          action: "UPDATE_USER_NAME",
          entity_type: "user",
          entity_id: current_user.id,
          payload: {
            user_id: current_user.id,
            user_email: current_user.email,
            old_name: old_name,
            new_name: current_user.name
          }
        )
      end

      render json: {
        success: true,
        message: "Settings updated successfully",
        user: {
          name: current_user.name,
          email: current_user.email,
          profile_image_url: current_user.profile_image.attached? ? helpers.user_profile_image_url(current_user) : nil,
          receive_notifications_on_email: current_user.receive_notifications_on_email
        }
      }, status: :ok
    else
      render json: {
        success: false,
        errors: current_user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def export_analytics
    unless current_user&.platform_admin?
      redirect_to dashboard_general_settings_path, alert: "You don't have permission to export analytics data."
      return
    end

    require "csv"

    # Collect analytics data
    analytics_data = collect_analytics_data

    # Generate CSV - Clean format with just data
    csv_data = CSV.generate(headers: true) do |csv|
      # Header row
      csv << [
        "Company Name",
        "Active Users",
        "License Seats",
        "License Utilization %",
        "Standards Assigned",
        "Compliance Rate %",
        "Status",
        "License Expiry Date",
        "Days Until Expiry"
      ]

      # Collect data for averages
      total_active_users = 0
      total_license_seats = 0
      total_license_utilization = 0
      total_standards = 0
      total_compliance = 0
      companies_count = analytics_data[:company_compliance].length
      companies_with_licenses = 0

      # Company data rows
      analytics_data[:company_compliance].each do |company_data|
        license_seats = company_data[:license_seats] || 0
        license_utilization = license_seats > 0 ?
          ((company_data[:active_users].to_f / license_seats) * 100).round(1) :
          0

        status = if company_data[:compliance_rate] >= 80
          "High Performance"
        elsif company_data[:compliance_rate] >= 50
          "Moderate Performance"
        else
          "Needs Improvement"
        end

        # Find license expiry info for this company
        license_info = analytics_data[:licenses_expiring_details].find { |l| l[:company_name] == company_data[:name] }
        expiry_date = license_info ? license_info[:expiry_date] : ""
        days_until_expiry = license_info ? license_info[:days_until_expiry] : ""

        csv << [
          company_data[:name],
          company_data[:active_users],
          license_seats,
          license_utilization,
          company_data[:standards_count],
          company_data[:compliance_rate].round(2),
          status,
          expiry_date,
          days_until_expiry
        ]

        # Accumulate for averages
        total_active_users += company_data[:active_users]
        total_license_seats += license_seats
        total_standards += company_data[:standards_count]
        total_compliance += company_data[:compliance_rate]

        if license_seats > 0
          total_license_utilization += license_utilization
          companies_with_licenses += 1
        end
      end

      # Add average row
      if companies_count > 0
        avg_license_utilization = companies_with_licenses > 0 ?
          (total_license_utilization / companies_with_licenses).round(1) : 0

        csv << [
          "AVERAGE",
          (total_active_users.to_f / companies_count).round(1),
          (total_license_seats.to_f / companies_count).round(1),
          avg_license_utilization,
          (total_standards.to_f / companies_count).round(1),
          (total_compliance / companies_count).round(2),
          "",
          "",
          ""
        ]
      end
    end

    # Log export action
    AuditLogService.log_action(
      actor_user: current_user,
      company: nil,
      action: "EXPORT_ANALYTICS",
      entity_type: "analytics",
      entity_id: nil,
      payload: {
        exported_at: Time.current.iso8601,
        exported_by: current_user.name,
        exported_by_email: current_user.email
      }
    )

    # Send CSV file
    send_data csv_data,
              filename: "platform_analytics_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
              type: "text/csv",
              disposition: "attachment"
  end

  private

  def collect_analytics_data
    # Total Active Users
    total_active_users = User.active.count
    active_users_count = User.where(is_active: true).count
    inactive_users_count = User.where(is_active: false).count
    pending_invitations_count = User.invited.count

    # Total Companies
    total_companies = Company.count
    companies_with_active_users = Company.joins(company_users: :user)
                                         .where(users: { is_active: true })
                                         .distinct
                                         .count
    companies_with_standards = Company.joins(:company_standards)
                                      .distinct
                                      .count

    # Total Standards
    total_standards = Standard.count
    standards_by_type = Standard.group(:code).count

    # Compliance Rate Calculation (assessments)
    total_assignments = Assessment.count
    completed_assignments = Assessment.where(status: "approved").count
    overall_compliance_rate = total_assignments > 0 ? ((completed_assignments.to_f / total_assignments) * 100).round(2) : 0

    # Company-level compliance
    company_compliance = Company.all.map do |company|
      total_company_assignments = Assessment.where(company_id: company.id).count
      completed_company_assignments = Assessment.where(company_id: company.id, status: "approved").count
      compliance_rate = total_company_assignments > 0 ? ((completed_company_assignments.to_f / total_company_assignments) * 100).round(2) : 0

      {
        name: company.name,
        active_users: company.company_users.joins(:user).where(users: { is_active: true }).count,
        standards_count: company.company_standards.count,
        compliance_rate: compliance_rate
      }
    end.sort_by { |c| -c[:compliance_rate] }

    # Licenses Expiring Soon (within 30 days)
    # Calculate expiry as created_at + 1 year (standard license period)
    now = Time.current
    thirty_days_from_now = 30.days.from_now

    # Get all companies and filter those expiring in next 30 days
    licenses_expiring_details = Company.all.map do |company|
      expiry_date = company.created_at + 1.year
      days_until_expiry = ((expiry_date - Time.current) / 1.day).ceil

      # Only include if expiring within 30 days
      next nil unless expiry_date >= now && expiry_date <= thirty_days_from_now

      current_users = company.company_users.joins(:user).where(users: { is_active: true }).count

      {
        company_name: company.name,
        license_seats: company.license_seats || 0,
        current_users: current_users,
        available_seats: [ (company.license_seats || 0) - current_users, 0 ].max,
        expiry_date: expiry_date.strftime("%Y-%m-%d"),
        days_until_expiry: days_until_expiry
      }
    end.compact.sort_by { |l| l[:days_until_expiry] }

    # Additional metrics
    average_compliance_rate = company_compliance.any? ? (company_compliance.sum { |c| c[:compliance_rate] } / company_compliance.length).round(2) : 0
    high_compliance_companies = company_compliance.count { |c| c[:compliance_rate] >= 80 }
    low_compliance_companies = company_compliance.count { |c| c[:compliance_rate] < 50 }

    # License metrics
    total_license_seats = Company.sum(:license_seats) || 0
    used_license_seats = User.joins(:company_user)
                             .where(is_active: true)
                             .where.not(company_users: { company_id: nil })
                             .count
    available_license_seats = [ total_license_seats - used_license_seats, 0 ].max

    # Credits metrics
    total_credits = Company.sum(:credits) || 0

    # Tools metrics
    total_tools = Tool.count

    # Evaluations metrics
    total_evaluations = AssignmentEvaluation.count

    # Add license seats to company compliance data
    company_compliance_with_seats = company_compliance.map do |company_data|
      company = Company.find_by(name: company_data[:name])
      company_data.merge(
        license_seats: company&.license_seats || 0
      )
    end

    {
      total_active_users: total_active_users,
      active_users_count: active_users_count,
      inactive_users_count: inactive_users_count,
      pending_invitations_count: pending_invitations_count,
      total_companies: total_companies,
      companies_with_active_users: companies_with_active_users,
      companies_with_standards: companies_with_standards,
      total_standards: total_standards,
      standards_by_type: standards_by_type,
      compliance_rate: overall_compliance_rate,
      company_compliance: company_compliance_with_seats,
      licenses_expiring_soon_count: licenses_expiring_details.count,
      licenses_expiring_details: licenses_expiring_details,
      total_assignments: total_assignments,
      completed_assignments: completed_assignments,
      average_compliance_rate: average_compliance_rate,
      high_compliance_companies: high_compliance_companies,
      low_compliance_companies: low_compliance_companies,
      total_license_seats: total_license_seats,
      used_license_seats: used_license_seats,
      available_license_seats: available_license_seats,
      total_credits: total_credits,
      total_tools: total_tools,
      total_evaluations: total_evaluations
    }
  end

  private

  def user_params
    params.require(:user).permit(:name, :profile_image, :receive_notifications_on_email)
  end
end
