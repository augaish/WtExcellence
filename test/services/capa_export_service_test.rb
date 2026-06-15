require "test_helper"
require "zip"

class CapaExportServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(
      name: "Test Co",
      license_seats: 5,
      credits: 100,
      is_active: true
    )

    @user = User.create!(
      email: "arabic-user@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Arabic User"
    )

    @company_user = CompanyUser.create!(
      company: @company,
      user: @user,
      role: CompanyUser::ROLES[:company_admin]
    )

    @capa = Capa.create!(
      company: @company,
      title: "Equipment calibration issue",
      description: "Calibration overdue for several devices",
      source: "internal_audit",
      priority: "high",
      status: "assigned"
    )

    CapaAssignment.create!(capa: @capa, company_user: @company_user)

    @action = CapaAction.create!(
      capa: @capa,
      title: "Action title",
      action_type: "Corrective",
      status: "Started",
      due_date: Date.today + 2,
      notes: "Action notes"
    )

    CapaActionAssignment.create!(capa_action: @action, company_user: @company_user)
  end

  test "generates arabic zip with capa and action csvs" do
    assert_equal "رمز CAPA", I18n.t("capa_export.headers.capa_code", locale: :ar)

    service = CapaExportService.new(Capa.all, "ar")
    zip_data = service.generate_zip
    capa_csv = read_zip_entry(zip_data, "capas.csv")
    actions_csv = read_zip_entry(zip_data, "actions.csv")

    # Ensure BOM is present and remove it for parsing
    bom = "\xEF\xBB\xBF"
    assert capa_csv.start_with?(bom), "Expected BOM at start of capa CSV"
    csv_body = capa_csv.sub(bom, "")

    rows = CSV.parse(csv_body)
    headers = rows.first
    data_row = rows.second

    expected_capa_headers = [
      "رمز CAPA",
      "العنوان",
      "الوصف",
      "الحالة",
      "الأولوية",
      "المصدر",
      "المعيار",
      "تاريخ الاستحقاق",
      "مُعيّن إلى",
      "تاريخ الإنشاء"
    ].reverse

    assert_equal expected_capa_headers, headers

    status_index = headers.index("الحالة")
    priority_index = headers.index("الأولوية")
    source_index = headers.index("المصدر")
    created_at_index = headers.index("تاريخ الإنشاء")

    assert_equal "مسندة", data_row[status_index]
    assert_equal "أولوية مرتفعة", data_row[priority_index]
    assert_equal "تدقيق داخلي", data_row[source_index]
    assert_equal @capa.created_at.strftime("%Y-%m-%d %H:%M:%S"), data_row[created_at_index]

    # Actions CSV
    assert actions_csv.start_with?(bom), "Expected BOM at start of actions CSV"
    actions_body = actions_csv.sub(bom, "")
    action_rows = CSV.parse(actions_body)
    action_headers = action_rows.first
    action_row = action_rows.second

    expected_action_headers = [
      "رمز CAPA",
      "العنوان",
      "نوع الإجراء",
      "الحالة",
      "تاريخ الاستحقاق",
      "ملاحظات",
      "مُعيّن إلى",
      "تاريخ الإنشاء"
    ].reverse

    assert_equal expected_action_headers, action_headers

    action_type_index = action_headers.index("نوع الإجراء")
    action_status_index = action_headers.index("الحالة")
    action_assignees_index = action_headers.index("مُعيّن إلى")

    assert_equal "تصحيحي", action_row[action_type_index]
    assert_equal "بدأ", action_row[action_status_index]
    assert_includes action_row[action_assignees_index], @user.name
  end

  private

  def read_zip_entry(zip_data, entry_name)
    zip_data = zip_data.string if zip_data.respond_to?(:string)
    content = nil
    Zip::File.open_buffer(zip_data) do |zip|
      data = zip.find_entry(entry_name).get_input_stream.read
      data = data.string if data.respond_to?(:string)
      content = data.to_s.dup.force_encoding("UTF-8")
    end
    content
  end
end

