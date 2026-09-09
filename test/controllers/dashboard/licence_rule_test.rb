require "test_helper"

# The licence rule across modules: a risk-manager licence works Governance
# and only reads Standards and P&P; a quality-manager licence works P&P and
# Standards and only reads Governance.
class Dashboard::LicenceRuleTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Lic #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @rm = user("lic-rm", CompanyUser::ROLES[:company_risk_manager])
    @qm = user("lic-qm", CompanyUser::ROLES[:company_quality_manager])
    @risk = Risk.create!(company: @company, title: "Supplier failure", likelihood: 3, impact: 3)
    @vendor = Vendor.create!(company: @company, name: "ACME")
    @policy = @company.pp_records.create!(record_type: "policy", title_en: "Leave policy")
  end

  test "a quality manager reads Governance but cannot write it" do
    sign_in @qm
    get dashboard_risk_management_index_path
    assert_response :success
    assert_select "a[href=?]", dashboard_edit_risk_path(@risk), count: 0
    get dashboard_vendors_path
    assert_response :success
    assert_select "a[href=?]", new_dashboard_vendor_path, count: 0

    post dashboard_vendors_path, params: { vendor: { name: "Sneak" } }
    refute Vendor.exists?(company_id: @company.id, name: "Sneak")
    patch dashboard_update_risk_path(@risk), params: { risk: { title: "Changed" } }
    assert_equal "Supplier failure", @risk.reload.title
  end

  test "a risk manager works Governance and reads P&P, Standards and the Library" do
    sign_in @rm
    post dashboard_vendors_path, params: { vendor: { name: "Allowed" } }
    assert Vendor.exists?(company_id: @company.id, name: "Allowed")

    get dashboard_pp_records_path
    assert_response :success
    assert_select "a[href=?]", new_dashboard_pp_record_path(record_type: nil), count: 0
    post dashboard_pp_records_path, params: { pp_record: { record_type: "policy", title_en: "Sneak" } }
    refute @company.pp_records.exists?(title_en: "Sneak")

    get dashboard_pp_processes_path
    assert_response :success
    get standards_path
    assert_response :success
    get library_path
    assert_response :success
    get dashboard_capa_management_path
    assert_redirected_to dashboard_risk_management_index_path
  end

  test "the sidebar shows each licence what it may open" do
    sign_in @rm
    get dashboard_overview_path
    assert_select "a[href=?]", dashboard_pp_records_path
    assert_select "a[href=?]", dashboard_risk_management_index_path

    sign_out @rm
    sign_in @qm
    get dashboard_overview_path
    assert_select "a[href=?]", dashboard_risk_management_index_path
    assert_select "a[href=?]", dashboard_vendors_path
  end

  private

  def user(tag, role)
    u = User.create!(email: "#{tag}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: tag, is_active: true)
    CompanyUser.create!(company: @company, user: u, role: role)
    u
  end
end
