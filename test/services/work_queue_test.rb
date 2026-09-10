require "test_helper"

# Section 5 of Review 03: the overview answers "what needs my action?" first,
# and a new company's admin sees what is still to set up.
class WorkQueueTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "WQ #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true, risk_appetite_score: 8)
    @user = User.create!(email: "wq-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Owner", is_active: true)
    @cu = CompanyUser.create!(company: @company, user: @user, role: CompanyUser::ROLES[:company_admin])
  end

  test "gathers my open CAPA actions, risks needing acceptance, overdue commitments, supplier reviews and pending authority reviews" do
    capa = Capa.create!(company_id: @company.id, title: "Late audit", description: "x", status: "open", priority: "medium", created_by_id: @user.id, source: "internal_audit")
    action = capa.capa_actions.create!(title: "Retrain staff", action_type: "corrective", status: "started", due_date: Date.current - 3, created_by_id: @user.id)
    CapaActionAssignment.create!(capa_action: action, company_user: @cu)
    capa.capa_actions.create!(title: "Proposed only", action_type: "corrective", status: "proposed", created_by_id: @user.id)
    Risk.create!(company: @company, title: "Above appetite", likelihood: 4, impact: 4, owner: @cu)
    CustomerCommitment.create!(company: @company, title: "Late report", customer_name: "Bank", due_date: Date.current - 1, owner: @cu)
    Vendor.create!(company: @company, name: "Stale supplier", owner: @cu, next_review_on: Date.current - 1)
    matrix = @company.pp_records.create!(record_type: "executive_doa", title_en: "DoA")
    matrix.matrix_reviews.create!(user: @user, requested_at: Time.current)

    titles = WorkQueue.new(user: @user, company: @company).items.map(&:title)
    assert_includes titles, "Retrain staff"
    refute_includes titles, "Proposed only", "a proposal is not yet anyone's work"
    assert_includes titles, "Above appetite"
    assert_includes titles, "Late report"
    assert_includes titles, "Stale supplier"
    assert_includes titles, "DoA"
    assert_equal "Retrain staff", WorkQueue.new(user: @user, company: @company).items.first.title, "the earliest due date comes first"
  end

  test "a bystander with nothing assigned has an empty queue" do
    other = User.create!(email: "wq2-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Other", is_active: true)
    CompanyUser.create!(company: @company, user: other, role: CompanyUser::ROLES[:company_viewer])
    assert WorkQueue.new(user: other, company: @company).empty?
  end

  test "the setup checklist ticks steps off as the company is set up" do
    checklist = SetupChecklist.new(@company)
    refute checklist.complete?
    assert_operator checklist.done_count, :<=, 1, "a fresh company has at most its default working week done"

    @company.update!(weekend_days: [ 5, 6 ])
    unit = @company.org_units.create!(name_en: "CEO", level: 1, head_user: @user)
    @cu.update!(pp_manager: true, role: CompanyUser::ROLES[:company_quality_manager])
    @company.pp_records.create!(record_type: "policy", title_en: "First policy", owner_org_unit: unit)

    checklist = SetupChecklist.new(@company.reload)
    done = checklist.steps.select(&:done?).map(&:key)
    assert_includes done, :working_days
    assert_includes done, :org_units
    assert_includes done, :unit_heads
    assert_includes done, :managers
    assert_includes done, :first_record
    refute_includes done, :branding
    refute_includes done, :standards
  end
end
