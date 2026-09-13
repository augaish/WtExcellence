# What one person can do in each area of the product, and why: the account
# role, the module licence, a workflow designation, or a unit headship. One
# place that answers "why can this person (not) act?" so an admin does not
# have to reason it out from five settings.
class EffectiveAccess
  Row = Struct.new(:area, :level, :reason, keyword_init: true)

  LEVELS = %w[manage read assigned none].freeze

  def initialize(user, company)
    @user = user
    @company = company
    @membership = user.company_user if user.company_user&.company_id == company.id
  end

  attr_reader :user, :company, :membership

  def role_key
    return "super_admin" if user.super_admin?
    return "delegated_admin" if user.delegated_admin?

    membership&.role || "none"
  end

  def designations
    return [] if membership.nil?

    list = []
    list << :pp_manager if membership.pp_manager?
    list << :gov_manager if membership.gov_manager?
    list
  end

  def headed_units
    company.org_units.active.where(head_user_id: user.id).ordered.to_a
  end

  def rows
    [
      row(:standards, quality_level, quality_reason),
      row(:capa, capa_level, capa_reason),
      row(:pp, pp_level, pp_reason),
      row(:documenter, documenter_level, documenter_reason),
      row(:authorities, authorities_level, authorities_reason),
      row(:governance, governance_level, governance_reason),
      row(:library, library_level, library_reason),
      row(:account_management, company_admin? ? "manage" : "none", company_admin? ? :company_admin : :not_company_admin),
      row(:branding, admin_privileges? ? "manage" : "none", admin_privileges? ? :admin_privileges : :no_admin_privileges),
      row(:activity, activity_level, activity_level == "read" ? :managers_read_activity : :not_a_manager)
    ]
  end

  # Things this company has not set up that limit what anyone can do.
  def setup_warnings
    warnings = []
    warnings << :no_pp_manager if company.module_enabled?(:pp) && company.company_users.where(pp_manager: true).none?
    warnings << :no_gov_manager if company.module_enabled?(:authorities) && company.company_users.where(gov_manager: true).none?
    headless = company.org_units.active.where(head_user_id: nil).count
    warnings << :units_without_head if headless.positive?
    warnings << :no_unit if membership && user.org_unit_id.nil?
    warnings
  end

  private

  def row(area, level, reason)
    Row.new(area: area, level: level, reason: reason)
  end

  def platform? = user.platform_admin?
  def company_admin? = platform? || membership&.company_admin? || false
  def admin_privileges? = platform? || membership&.has_admin_privileges? || false
  def role?(name) = membership&.public_send("company_#{name}?") || false

  def quality_level
    return "manage" if admin_privileges?
    return "read" if role?(:risk_manager) || role?(:viewer)
    return "assigned" if role?(:auditor) || role?(:contributor)
    "none"
  end

  def quality_reason
    return :platform if platform?
    return :quality_licence if admin_privileges?
    return :risk_manager_reads if role?(:risk_manager)
    return :viewer_reads if role?(:viewer)
    :assigned_only
  end

  def capa_level
    return "manage" if admin_privileges?
    return "none" if role?(:risk_manager)
    return "read" if role?(:viewer)
    "assigned"
  end

  def capa_reason
    return :platform if platform?
    return :quality_licence if admin_privileges?
    return :risk_manager_no_capa if role?(:risk_manager)
    return :viewer_reads if role?(:viewer)
    :assigned_only
  end

  def pp_level
    return "manage" if admin_privileges?
    return "read" if role?(:risk_manager) || role?(:viewer) || role?(:auditor)
    "assigned"
  end

  def pp_reason
    return :platform if platform?
    return :quality_licence if admin_privileges?
    return :assigned_only if role?(:contributor)
    :reads_records
  end

  def documenter_level
    return "manage" if platform? || membership&.pp_manager? || membership&.company_admin?
    return "assigned" if membership
    "none"
  end

  def documenter_reason
    return :platform if platform?
    return :pp_manager_designation if membership&.pp_manager?
    return :company_admin if membership&.company_admin?
    return :quality_manager_not_designated if role?(:quality_manager)
    :stage_actor_only
  end

  def authorities_level
    return "manage" if platform? || membership&.company_admin? || membership&.gov_manager?
    return "read" if membership&.can_view_governance? || role?(:viewer) || role?(:auditor) || role?(:contributor)
    "none"
  end

  def authorities_reason
    return :platform if platform?
    return :company_admin if membership&.company_admin?
    return :gov_manager_designation if membership&.gov_manager?
    return :risk_manager_not_designated if role?(:risk_manager)
    :reads_matrix
  end

  def governance_level
    return "manage" if platform? || membership&.can_manage_governance?
    return "read" if membership&.can_view_governance?
    "assigned"
  end

  def governance_reason
    return :platform if platform?
    return :governance_licence if membership&.can_manage_governance?
    return :quality_manager_reads if membership&.can_view_governance?
    :assigned_tasks_only
  end

  def library_level
    return "read" if role?(:viewer) || (role?(:risk_manager) && !platform?)
    membership || platform? ? "manage" : "none"
  end

  def library_reason
    return :viewer_reads if role?(:viewer)
    return :risk_manager_reads if role?(:risk_manager) && !platform?
    :members_write_library
  end

  def activity_level
    return "read" if platform? || membership&.has_admin_privileges? || role?(:risk_manager)
    "none"
  end
end
