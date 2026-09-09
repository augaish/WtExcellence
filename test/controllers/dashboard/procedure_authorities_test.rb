require "test_helper"

# Steps and the operational authorities behind each step, written in the
# Documenter on the procedure record.
class Dashboard::ProcedureAuthoritiesTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Detail Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = create_user("detail-admin", CompanyUser::ROLES[:company_admin])
    @viewer = create_user("detail-viewer", CompanyUser::ROLES[:company_viewer])
    @minister = @company.org_units.create!(name_en: "Minister", level: 1)
    @deputy = @company.org_units.create!(name_en: "Deputy", level: 2, parent: @minister)
    @director = @company.org_units.create!(name_en: "Director", level: 3, parent: @deputy)

    @matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "Executive DoA")
    @executive = @company.authorities.create!(matrix: @matrix, name_en: "Sign contracts")
    @executive.default_band.assignments.create!(level: "authorize", org_unit: @deputy)

    @procedure = @company.pp_records.create!(record_type: "procedure", title_en: "Develop a policy",
      pp_process: level_two_process(@company), current_stage: "s2_prep")
    @step = @procedure.steps.create!(position: 1, activity: "Award the contract")
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "steps are numbered on the procedure and the process has no detail page" do
    sign_in @admin
    3.times { |i| post dashboard_pp_record_record_steps_path(@procedure), params: { pp_process_step: { activity: "Step #{i}" } } }
    assert_equal [ 1, 2, 3, 4 ], @procedure.steps.ordered.pluck(:position)

    get "/dashboard/pp_processes/#{@procedure.pp_process_id}"
    assert_response :not_found
  end

  test "an operational authority is added behind a step, with its holders, and checked against the executive one" do
    sign_in @admin
    post dashboard_pp_record_operational_authorities_path(@procedure, step_id: @step.id), params: {
      pp_process_authority: { decision: "Award below SAR 1m", authority_id: @executive.id }
    }
    authority = @procedure.operational_authorities.sole
    assert_equal @step, authority.pp_process_step

    post dashboard_pp_record_operational_authority_assignments_path(@procedure, authority), params: {
      pp_authority_assignment: { level: "authorize", org_unit_id: @director.id }
    }
    refute authority.reload.conforms_to_executive?, "a director may not authorize what the matrix gives the deputy"

    get dashboard_documenter_record_path(@procedure)
    assert_response :success
    assert_select "#step_authorities_#{@step.id}", text: /#{Regexp.escape(I18n.t('process_authorities.not_conforming'))}/

    authority.assignments.destroy_all
    post dashboard_pp_record_operational_authority_assignments_path(@procedure, authority), params: {
      pp_authority_assignment: { level: "authorize", org_unit_id: @minister.id }
    }
    assert authority.reload.conforms_to_executive?, "higher up the hierarchy always conforms"
  end

  test "the page reports a decision nobody may finally authorize and a segregation breach" do
    authority = @procedure.operational_authorities.create!(decision: "Award the contract", pp_process_step: @step)
    authority.assignments.create!(level: "prepare", holder_title: "Procurement Officer")
    sign_in @admin
    get dashboard_documenter_record_path(@procedure)
    assert_select "p", text: I18n.t("process_authorities.no_authorizer")

    %w[review authorize].each { |level| authority.assignments.create!(level: level, holder_title: "Procurement Officer") }
    get dashboard_documenter_record_path(@procedure)
    assert_select "p", text: I18n.t("process_authorities.segregation_breach")
  end

  test "the document prints the procedure's own operational matrix" do
    authority = @procedure.operational_authorities.create!(decision: "Award the contract", pp_process_step: @step)
    authority.assignments.create!(level: "authorize", org_unit: @deputy)
    section = RecordDocument.new(@procedure).sections.find { |s| s.key == "authority_matrix" }
    assert_equal "Award the contract", section.payload.first[:decision]
  end

  test "a viewer cannot write operational authorities" do
    sign_in @viewer
    post dashboard_pp_record_operational_authorities_path(@procedure, step_id: @step.id), params: { pp_process_authority: { decision: "Sneak" } }
    assert_equal 0, @procedure.operational_authorities.count
  end
end
