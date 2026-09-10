require "test_helper"

# Inviting a company's users from Excel, from the super admin's company page.
class Dashboard::UserImportTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Import Co #{SecureRandom.hex(4)}", license_seats: 4, credits: 50, is_active: true)
    @admin = User.create!(email: "imp-admin-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Company Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    @super_admin = User.create!(email: "root-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Root", role: "super_admin", is_active: true)
    @unit = @company.org_units.create!(name_en: "Quality", level: 1)
  end

  def workbook(rows, with_seats_line: true)
    file = Tempfile.new([ "users", ".xlsx" ])
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Users") do |sheet|
        sheet.add_row [ "3 of 4 seats free" ] if with_seats_line
        sheet.add_row UserImportTemplate::HEADERS
        rows.each { |row| sheet.add_row row }
      end
      p.serialize(file.path)
    end
    Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end

  test "the company page offers the upload to the super admin and the template matches the free seats" do
    sign_in @super_admin
    get dashboard_account_management_company_path(@company)
    assert_select "a[href=?]", dashboard_account_management_import_users_path(@company)

    get dashboard_account_management_import_users_path(@company)
    assert_response :success
    assert_includes response.body, I18n.t("user_import.seats_line", free: 3, total: 4)

    get dashboard_account_management_users_template_path(@company)
    assert_response :success
    book = Roo::Excelx.new(StringIO.new(response.body), file_warning: :ignore)
    users = book.sheet("Users")
    assert_equal I18n.t("user_import.seats_line", free: 3, total: 4), users.row(1).first
    assert_equal [ "Name", "Email", "Role", "Organizational unit" ], users.row(2)
    lists = book.sheet("Lists")
    assert_includes lists.column(1), "Quality manager"
    assert_includes lists.column(2), "Quality"
  end

  test "a company admin has no upload button and cannot reach the page" do
    sign_in @admin
    get dashboard_account_management_company_path(@company)
    assert_select "a[href=?]", dashboard_account_management_import_users_path(@company), 0

    get dashboard_account_management_import_users_path(@company)
    assert_redirected_to dashboard_account_management_path
  end

  test "a good sheet invites everyone with the same invitation as Add user" do
    sign_in @super_admin
    assert_emails 2 do
      perform_enqueued_jobs do
        post dashboard_account_management_import_users_path(@company), params: { file: workbook([
          [ "Sara Ali", "sara-#{SecureRandom.hex(3)}@example.com", "Quality manager", "Quality" ],
          [ "Omar Said", "omar-#{SecureRandom.hex(3)}@example.com", "company_viewer", nil ]
        ]) }
      end
    end
    assert_redirected_to dashboard_account_management_company_path(@company)
    follow_redirect!
    assert_includes response.body, I18n.t("user_import.done", count: 2, free: 1)

    sara = User.find_by(name: "Sara Ali")
    assert_not sara.is_active
    assert sara.invitation_token.present?
    assert_equal @super_admin, sara.invited_by
    assert_equal @unit, sara.org_unit
    assert_equal "company_quality_manager", sara.company_user.role
    assert_equal "company_viewer", User.find_by(name: "Omar Said").company_user.role
    assert AuditLog.exists?(entity_id: sara.id, action: "CREATE_USER_INVITATION")
  end

  test "more rows than free seats refuses the whole file" do
    sign_in @super_admin
    rows = 4.times.map { |i| [ "Person #{i}", "p#{i}-#{SecureRandom.hex(3)}@example.com", "Viewer", nil ] }
    assert_no_difference "User.count" do
      post dashboard_account_management_import_users_path(@company), params: { file: workbook(rows) }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("user_import.too_many_rows", rows: 4, free: 3)
  end

  test "a bad row names itself and nothing is saved" do
    sign_in @super_admin
    assert_no_difference "User.count" do
      post dashboard_account_management_import_users_path(@company), params: { file: workbook([
        [ "Good Person", "good-#{SecureRandom.hex(3)}@example.com", "Viewer", nil ],
        [ "", "not-an-email", "Chief", "Nowhere" ],
        [ "Twice", @admin.email, "Viewer", nil ]
      ]) }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("user_import.row", number: 4)
    assert_includes response.body, I18n.t("user_import.name_required")
    assert_includes response.body, CGI.escapeHTML(I18n.t("user_import.role_unknown", role: "Chief"))
    assert_includes response.body, CGI.escapeHTML(I18n.t("user_import.unit_unknown", unit: "Nowhere"))
    assert_includes response.body, I18n.t("user_import.email_taken", email: @admin.email)
  end
end
