# Who may add and edit records.
#
# The product owner's rule: the company admin, quality managers, and the
# admin's own team - everyone whose unit reports to a unit the admin heads,
# directly or through the chain. A contributor elsewhere in the structure can
# read what is published but does not author it.
class RecordAuthoring
  def self.allowed?(user, company)
    new(user, company).allowed?
  end

  def initialize(user, company)
    @user = user
    @company = company
  end

  def allowed?
    return false if user.nil? || company.nil?
    return true if user.platform_admin?

    membership = user.company_user
    return false if membership.nil? || membership.company_id != company.id
    return true if membership.company_admin? || membership.company_quality_manager?

    in_an_admins_team?
  end

  private

  attr_reader :user, :company

  def in_an_admins_team?
    return false if user.org_unit_id.blank?

    admin_ids = company.company_users.where(role: CompanyUser::ROLES[:company_admin]).pluck(:user_id)
    return false if admin_ids.empty?

    company.org_units.where(head_user_id: admin_ids).any? do |unit|
      unit.id == user.org_unit_id || unit.descendant_ids.include?(user.org_unit_id)
    end
  end
end
