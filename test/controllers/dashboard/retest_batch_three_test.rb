require "test_helper"

# R13, R16 and R17 — the parts of them a server can prove.
class Dashboard::RetestBatchThreeTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "B3 Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = User.create!(email: "b3-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "B3 Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    sign_in @admin
  end

  # R13
  test "a rejected service level keeps the other fields the user typed" do
    sla = @company.pp_records.create!(record_type: "sla", title_en: "SLA")
    post dashboard_pp_record_service_levels_path(sla), params: {
      pp_service_level: { service_name: "Portal", metric: "availability", target_value: 4, target_unit: "hours",
                          measurement_method: "Uptime report", coverage: "24x7", remedy: "Credit" }
    }
    assert_equal 0, sla.service_levels.count
    follow_redirect!

    assert_select "input[name=?][value=?]", "pp_service_level[service_name]", "Portal"
    assert_select "input[name=?][value=?]", "pp_service_level[measurement_method]", "Uptime report"
    assert_select "input[name=?][value=?]", "pp_service_level[remedy]", "Credit"
  end

  test "a rejected step keeps what was typed" do
    procedure = @company.pp_records.create!(record_type: "procedure", title_en: "P", pp_process: level_two_process(@company), current_stage: "s2_prep")
    post dashboard_pp_record_record_steps_path(procedure), params: {
      pp_process_step: { activity: "Draft", responsible_title: "Officer", duration_value: 2 }
    }
    follow_redirect!
    assert_select "input[name=?][value=?]", "pp_process_step[activity]", "Draft"
    assert_select "input[name=?][value=?]", "pp_process_step[responsible_title]", "Officer"
  end

  test "a rejected temporary delegation keeps its parties and dates" do
    matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "DoA")
    authority = @company.authorities.create!(matrix: matrix, name_en: "X")
    a = @company.org_units.create!(name_en: "A", level: 1)
    b = @company.org_units.create!(name_en: "B", level: 2, parent: a)

    post dashboard_create_authority_delegation_path(matrix_id: matrix.id), params: {
      authority_delegation: { authority_id: authority.id, from_org_unit_id: a.id, to_org_unit_id: b.id,
                              kind: "temporary", status: "active", valid_from: "2026-09-01" }
    }
    assert_equal 0, @company.authority_delegations.count
    follow_redirect!
    assert_select "select[name=?] option[selected][value=?]", "authority_delegation[from_org_unit_id]", a.id
    assert_select "input[name=?][value=?]", "authority_delegation[valid_from]", "2026-09-01"
  end

  # R16
  test "the header balance is marked so the assistant can refresh it" do
    get dashboard_overview_path
    assert_select "[data-credit-balance]", minimum: 1
  end

  # R17
  test "every CAPA modal control has an accessible name" do
    capa = Capa.create!(company: @company, title: "QA", priority: "medium", status: "Open",
      description: "d", source: "audit", created_by_id: @admin.id)
    get dashboard_capa_management_show_path(capa)

    %w[capa[title] capa[description] capa[source] capa[priority] capa[due_date] capa[status]].each do |name|
      assert_select "[name=?][aria-label]", name, { minimum: 1 }, "#{name} has no accessible name"
    end
  end

  test "the org chart exposes its nodes and offers a textual tree" do
    parent = @company.org_units.create!(name_en: "Minister", level: 1)
    @company.org_units.create!(name_en: "Deputy", level: 2, parent: parent)
    get dashboard_org_units_chart_path

    assert_select "svg[role=group] title"
    assert_select "svg [role=button][aria-label=?]", "Deputy"
    assert_select "ul.sr-only li", text: /Deputy.*Minister/m
  end

  test "statuses read in Arabic and dates carry no time" do
    commitment = @company.customer_commitments.create!(title: "Report", customer_name: "X", due_date: Date.new(2026, 9, 8))
    get dashboard_customer_commitment_path(commitment, locale: "ar")

    assert_includes response.body, I18n.t("commitment_status.open", locale: :ar)
    assert_not_includes response.body, "Open</span>"
    assert_not_includes response.body, "Sep 08, 2026"
  end
end
