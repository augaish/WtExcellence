require "test_helper"

# Test team items 1, 3 and 20.
class Group3FixesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "G3 Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @admin = create_user("admin", CompanyUser::ROLES[:company_admin])
    @member = create_user("member", CompanyUser::ROLES[:company_viewer])
    @other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @outsider = User.create!(email: "out-#{SecureRandom.hex(4)}@example.com", password: "Password1234", password_confirmation: "Password1234", name: "Out", is_active: true)
    CompanyUser.create!(company: @other, user: @outsider, role: CompanyUser::ROLES[:company_viewer])
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: prefix.humanize, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "1: the company admin changes a member's email; both addresses are told; another company's member is out of reach" do
    sign_in @admin
    get dashboard_user_access_path(@member)
    assert_select "form[action=?]", dashboard_change_user_email_path(@member)

    old = @member.email
    assert_enqueued_emails 1 do
      patch dashboard_change_user_email_path(@member), params: { email: "New.Address@example.com" }
    end
    assert_equal "new.address@example.com", @member.reload.email
    perform_enqueued_jobs
    assert_equal [ "new.address@example.com", old ].sort, ActionMailer::Base.deliveries.last.to.sort

    patch dashboard_change_user_email_path(@member), params: { email: @admin.email }
    assert_equal "new.address@example.com", @member.reload.email, "a taken address is refused"

    patch dashboard_change_user_email_path(@outsider), params: { email: "x@example.com" }
    assert_redirected_to dashboard_account_management_users_path
    assert_not_equal "x@example.com", @outsider.reload.email
  end

  test "3: a reset link is sent instead of an admin choosing the password" do
    sign_in @admin
    assert_enqueued_emails 1 do
      post dashboard_send_user_reset_link_path(@member)
    end
    assert @member.reload.reset_password_token.present?
    assert AuditLog.exists?(entity_id: @member.id, action: "SEND_PASSWORD_RESET_LINK")
  end

  test "20: a form is built from fields and tables and printed as a fillable layout" do
    form = @company.pp_records.create!(record_type: "form", title_en: "Evidence Checklist", scope: "x")
    sign_in @admin
    post dashboard_pp_record_form_fields_path(form), params: { pp_form_field: { label_en: "Request reference", field_type: "text", required: "1" } }
    post dashboard_pp_record_form_fields_path(form), params: { pp_form_field: { label_en: "Decision", field_type: "choice", options: "Accepted | Rejected" } }
    post dashboard_pp_record_form_fields_path(form), params: { pp_form_field: { label_en: "Evidence", field_type: "table", columns: "Item | Reference | Date" } }
    fields = form.form_fields.reload.to_a
    assert_equal [ 1, 2, 3 ], fields.map(&:position)

    patch dashboard_pp_record_reorder_form_fields_path(form), params: { ids: [ fields[2].id, fields[0].id, fields[1].id ] }, as: :json
    assert_equal %w[Evidence Request\ reference Decision], form.form_fields.reload.map(&:label_en)

    get dashboard_pp_record_path(form)
    assert_select "#form-fields li", 3
    get document_dashboard_pp_record_path(form)
    assert_select "th", text: "Reference"
    assert_includes response.body, "☐ Accepted"

    docx = RecordDocxRenderer.new(RecordDocument.new(form.reload, locale: :en)).render
    xml = nil
    Zip::File.open_buffer(StringIO.new(docx)) { |zip| xml = zip.read("word/document.xml") }
    assert_includes xml, "Request reference *"
    assert_includes xml, "Reference"

    successor = RecordVersionService.new(form.tap { |f| f.update!(current_stage: PpStage::TERMINAL_KEYS.first, published_at: Time.current) }, actor: @admin).open_next
    assert_equal 3, successor.form_fields.count
  end
end
