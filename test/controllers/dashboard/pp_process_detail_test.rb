require "test_helper"

# The procedure detail page: خطوات الإجراء and مصفوفة الصلاحيات الإجرائية, the two
# sections a generated procedure document needs and the module did not hold.
class Dashboard::PpProcessDetailTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Detail Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = create_user("detail-admin", CompanyUser::ROLES[:company_admin])
    @viewer = create_user("detail-viewer", CompanyUser::ROLES[:company_viewer])
    @process = @company.pp_processes.create!(name_en: "Policy development", level: 1, category: "core", code: "PRO-01")
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "the detail page shows both sections" do
    sign_in @admin
    get dashboard_pp_process_path(@process)

    assert_response :success
    assert_select "h2", text: I18n.t("process_steps.title")
    assert_select "h2", text: I18n.t("process_authorities.title")
  end

  test "a step can be added and appears with its duration" do
    sign_in @admin
    post dashboard_pp_process_steps_path(@process), params: {
      pp_process_step: { activity: "Draft the policy", responsible_title: "Policies Director",
                         duration_value: 3, duration_unit: "days" }
    }

    assert_redirected_to dashboard_pp_process_path(@process)
    step = @process.steps.sole
    assert_equal 1, step.position
    assert_equal "Policies Director", step.responsible_label

    follow_redirect!
    assert_includes response.body, "Draft the policy"
  end

  test "steps are numbered in the order they are added" do
    sign_in @admin
    3.times do |index|
      post dashboard_pp_process_steps_path(@process), params: {
        pp_process_step: { activity: "Step #{index}" }
      }
    end

    assert_equal [ 1, 2, 3 ], @process.steps.ordered.pluck(:position)
  end

  test "a duration without a unit is refused with a readable message" do
    sign_in @admin
    post dashboard_pp_process_steps_path(@process), params: {
      pp_process_step: { activity: "Draft", duration_value: 2 }
    }

    assert_equal 0, @process.steps.count
    assert_includes flash[:alert], I18n.t("process_steps.errors.unit_required")
  end

  test "the page reports a decision that nobody may finally authorize" do
    authority = @process.authorities.create!(decision: "Award the contract")
    authority.assignments.create!(level: "prepare", holder_title: "Procurement Officer")

    sign_in @admin
    get dashboard_pp_process_path(@process)

    assert_select "p", text: I18n.t("process_authorities.no_authorizer")
  end

  test "the page reports a segregation of duties breach" do
    authority = @process.authorities.create!(decision: "Award the contract")
    %w[prepare review authorize].each do |level|
      authority.assignments.create!(level: level, holder_title: "Procurement Director")
    end

    sign_in @admin
    get dashboard_pp_process_path(@process)

    assert_select "p", text: I18n.t("process_authorities.segregation_breach")
  end

  test "an authority and its assignment can be added" do
    sign_in @admin
    post dashboard_pp_process_authorities_path(@process), params: {
      pp_process_authority: { item: "Direct purchase", decision: "Award below SAR 1m" }
    }
    authority = @process.authorities.sole

    post dashboard_pp_process_authority_assignments_path(@process, authority), params: {
      pp_authority_assignment: { level: "authorize", holder_title: "Procurement Director",
                                 condition: "Where within budget" }
    }

    assignment = authority.assignments.sole
    assert_equal "authorize", assignment.level
    assert_equal "Where within budget", assignment.condition
    assert authority.reload.single_authorizer?
  end

  test "a viewer cannot edit the procedure detail" do
    sign_in @viewer
    post dashboard_pp_process_steps_path(@process), params: { pp_process_step: { activity: "Sneak" } }

    assert_redirected_to dashboard_pp_processes_path
    assert_equal 0, @process.steps.count
  end

  test "a process from another company is not reachable" do
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 1, is_active: true)
    foreign = other.pp_processes.create!(name_en: "Foreign", level: 1, category: "core")

    sign_in @admin
    get dashboard_pp_process_path(foreign)

    assert_redirected_to dashboard_pp_processes_path
  end
end
