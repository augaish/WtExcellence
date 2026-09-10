# The first things a new company must have before the product works as
# intended, in dependency order, each with where to do it. Shown to company
# admins until every step is done.
class SetupChecklist
  Step = Struct.new(:key, :done, :path, keyword_init: true) do
    def done? = done
  end

  def initialize(company)
    @company = company
    @routes = Rails.application.routes.url_helpers
  end

  # Steps for modules the company has switched off are left out: a checklist
  # must not send anyone to a page that does not exist for them.
  def steps
    @steps ||= [
      Step.new(key: :branding, done: company.brand_logo.attached?, path: routes.dashboard_branding_path),
      (Step.new(key: :working_days, done: company.weekend_days.present?, path: routes.dashboard_general_settings_documenter_path) if company.module_enabled?(:pp)),
      (Step.new(key: :org_units, done: company.org_units.active.exists?, path: routes.dashboard_org_units_path) if company.module_enabled?(:org_structure)),
      (Step.new(key: :unit_heads, done: company.org_units.active.where(level: 1).exists? && company.org_units.active.where(level: 1, head_user_id: nil).none?, path: routes.dashboard_org_units_path) if company.module_enabled?(:org_structure)),
      Step.new(key: :managers, done: company.company_users.where(pp_manager: true).exists? || company.company_users.where(gov_manager: true).exists?, path: routes.dashboard_account_management_users_path),
      (Step.new(key: :standards, done: CompanyStandard.where(company_id: company.id, status: "active").exists?, path: routes.standards_path) if company.module_enabled?(:standards)),
      (Step.new(key: :first_record, done: company.pp_records.where(record_type: PpRecord::TAB_TYPES).exists?, path: routes.dashboard_pp_records_path) if company.module_enabled?(:pp))
    ].compact
  end

  def complete?
    steps.all?(&:done?)
  end

  def done_count
    steps.count(&:done?)
  end

  private

  attr_reader :company, :routes
end
