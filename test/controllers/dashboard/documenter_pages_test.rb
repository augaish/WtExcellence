require "test_helper"

# Every stage panel renders for the people who see it. A broken partial on a
# stage nobody tested would only surface when a real record got there.
class Dashboard::DocumenterPagesTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Pages Co #{SecureRandom.hex(4)}", license_seats: 20, credits: 50, is_active: true)
    @ppm = user("pages-ppm", CompanyUser::ROLES[:company_quality_manager], pp_manager: true)
    @head = user("pages-head", CompanyUser::ROLES[:company_contributor])
    @reporter = user("pages-rep", CompanyUser::ROLES[:company_contributor])
    @unit = @company.org_units.create!(name_en: "Finance", level: 1, code: "FIN", head_user: @head)
    @reporter.update!(org_unit: @unit)
  end

  test "the flow page renders at every stage of every route, for the manager and the unit head" do
    records = {
      "policy" => @company.pp_records.create!(record_type: "policy", title_en: "Policy", owner_org_unit: @unit),
      "procedure" => @company.pp_records.create!(record_type: "procedure", title_en: "Procedure", owner_org_unit: @unit, pp_process: level_two_process(@company)),
      "service" => @company.pp_records.create!(record_type: "service", title_en: "Service", owner_org_unit: @unit),
      "glossary" => @company.pp_records.create!(record_type: "glossary", title_en: "Term", description: "Meaning")
    }
    records["policy"].clauses.create!(title: "Purpose", body: "Why").tap { |c| c.comments.create!(user: @ppm, body: "Note") }
    records["procedure"].steps.create!(position: 1, activity: "Do it")
    records["policy"].stage_approvals.create!(stage_key: "s2_stakeholders", org_unit: @unit, requested_at: Time.current)

    records.each do |type, record|
      PpStage.route_for(record_type: type).each do |key|
        record.update_columns(current_stage: key)
        record.stage_tasks.create!(stage_key: key, user: @reporter, assigned_at: Time.current) if key == "s2_prep"

        [ @ppm, @head, @reporter ].each do |viewer|
          sign_in viewer
          get dashboard_documenter_record_path(record)
          assert_response :success, "#{type} at #{key} for #{viewer.name}"
          sign_out viewer
        end
      end
    end
  end

  test "the worklist and the record page render for a manager with records everywhere" do
    PpStage::DOCUMENT_ROUTE.each_with_index do |key, i|
      @company.pp_records.create!(record_type: "policy", title_en: "Doc #{i}", owner_org_unit: @unit, current_stage: key)
    end
    sign_in @ppm
    PpStage::PHASES.each do |phase|
      get dashboard_documenter_path(phase: phase)
      assert_response :success
    end
    get dashboard_pp_record_path(@company.pp_records.first)
    assert_response :success
  end

  test "the PDF page is built from the same document with the stylesheet inlined" do
    record = @company.pp_records.create!(record_type: "policy", title_en: "Policy", title_ar: "سياسة", owner_org_unit: @unit)
    record.clauses.create!(title: "Purpose", body: "Why")
    html = RecordPdfRenderer.new(record, locale: :ar).html

    assert_includes html, 'dir="rtl"'
    assert_includes html, "Purpose"
    assert_includes html, "<style>"
    refute_includes html, "stylesheet_link_tag"
    assert_match(/\.pdf\z/, RecordPdfRenderer.new(record, locale: :ar).filename)
  end

  private

  def user(tag, role, pp_manager: false)
    u = User.create!(email: "#{tag}-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: tag, is_active: true)
    CompanyUser.create!(company: @company, user: u, role: role, pp_manager: pp_manager)
    u
  end
end
