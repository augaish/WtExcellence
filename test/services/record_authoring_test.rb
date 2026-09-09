require "test_helper"

# Who may add records: the admin, the quality managers, and everyone who
# reports - directly or through the chain - to a unit the admin heads.
class RecordAuthoringTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Auth #{SecureRandom.hex(4)}", license_seats: 10, is_active: true)
    @admin = user("admin", CompanyUser::ROLES[:company_admin])
    @qm = user("qm", CompanyUser::ROLES[:company_quality_manager])
    @team = user("team", CompanyUser::ROLES[:company_contributor])
    @deep = user("deep", CompanyUser::ROLES[:company_contributor])
    @outsider = user("outsider", CompanyUser::ROLES[:company_contributor])

    excellence = @company.org_units.create!(name_en: "Excellence", level: 1, head_user: @admin)
    quality = @company.org_units.create!(name_en: "Quality", level: 2, parent: excellence)
    methods = @company.org_units.create!(name_en: "Methods", level: 3, parent: quality)
    finance = @company.org_units.create!(name_en: "Finance", level: 1)

    @team.update!(org_unit: quality)
    @deep.update!(org_unit: methods)
    @outsider.update!(org_unit: finance)
  end

  test "admins and quality managers always may" do
    assert RecordAuthoring.allowed?(@admin, @company)
    assert RecordAuthoring.allowed?(@qm, @company)
  end

  test "the admin's team may, however deep the chain" do
    assert RecordAuthoring.allowed?(@team, @company)
    assert RecordAuthoring.allowed?(@deep, @company)
  end

  test "a contributor outside the admin's chain may not" do
    refute RecordAuthoring.allowed?(@outsider, @company)
  end

  test "a contributor with no unit may not" do
    @team.update!(org_unit: nil)
    refute RecordAuthoring.allowed?(@team, @company)
  end

  private

  def user(tag, role)
    u = User.create!(email: "#{tag}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: tag.capitalize, is_active: true)
    CompanyUser.create!(company: @company, user: u, role: role)
    u
  end
end
