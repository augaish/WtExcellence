require "test_helper"

class Dashboard::PpPackagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "PkgCtl #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)

    @admin = User.create!(email: "pkg-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])

    @viewer = User.create!(email: "pkg-viewer-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: "Viewer", is_active: true)
    CompanyUser.create!(company: @company, user: @viewer, role: CompanyUser::ROLES[:company_viewer])

    @pkg_a = @company.pp_packages.create!(name: "Package A")
    @pkg_b = @company.pp_packages.create!(name: "Package B")
    @record = @company.pp_records.create!(record_type: "policy", title_en: "Data Policy", code: "POL-01")
  end

  test "index lists packages" do
    sign_in @admin
    get dashboard_pp_packages_path

    assert_response :success
    assert_select "body", text: /Package A/
  end

  test "show renders a checklist per record type" do
    sign_in @admin
    get dashboard_pp_package_path(@pkg_a, record_type: "policy")

    assert_response :success
    assert_select "body", text: /Data Policy/
  end

  test "admin creates a package" do
    sign_in @admin

    assert_difference -> { @company.pp_packages.count }, 1 do
      post dashboard_pp_packages_path, params: {
        pp_package: { name: "Q2 Cycle", start_date: "2026-04-01", end_date: "2026-06-30", notes: "Spring batch" }
      }
    end

    assert_equal "Q2 Cycle", @company.pp_packages.order(:created_at).last.name
  end

  test "a viewer cannot create a package" do
    sign_in @viewer

    assert_no_difference -> { @company.pp_packages.count } do
      post dashboard_pp_packages_path, params: { pp_package: { name: "Sneaky" } }
    end
    assert_redirected_to dashboard_pp_packages_path
  end

  test "assigning an unpackaged record adds it" do
    sign_in @admin

    post assign_record_dashboard_pp_package_path(@pkg_a, record_id: @record.id, record_type: "policy")

    assert_equal @pkg_a.id, @record.reload.package_id
  end

  # Server-side enforcement: the API itself refuses to move a committed record.
  test "assigning a record that belongs to another package is refused" do
    sign_in @admin
    @record.update!(package: @pkg_a)

    post assign_record_dashboard_pp_package_path(@pkg_b, record_id: @record.id, record_type: "policy")

    assert_equal @pkg_a.id, @record.reload.package_id, "the record must not have moved"
    assert_match(/Package A/, flash[:alert].to_s)
  end

  test "an explicit re-assign moves the record" do
    sign_in @admin
    @record.update!(package: @pkg_a)

    post assign_record_dashboard_pp_package_path(@pkg_b, record_id: @record.id, record_type: "policy", reassign: true)

    assert_equal @pkg_b.id, @record.reload.package_id
  end

  test "removing a record unpackages it" do
    sign_in @admin
    @record.update!(package: @pkg_a)

    delete remove_record_dashboard_pp_package_path(@pkg_a, record_id: @record.id, record_type: "policy")

    assert_nil @record.reload.package_id
    assert PpRecord.exists?(@record.id)
  end

  test "a viewer cannot compose a package" do
    sign_in @viewer

    post assign_record_dashboard_pp_package_path(@pkg_a, record_id: @record.id, record_type: "policy")

    assert_nil @record.reload.package_id
  end

  test "a record from another company cannot be assigned" do
    sign_in @admin
    other = Company.create!(name: "Other #{SecureRandom.hex(4)}", license_seats: 1, is_active: true)
    foreign = other.pp_records.create!(record_type: "policy", title_en: "Foreign")

    post assign_record_dashboard_pp_package_path(@pkg_a, record_id: foreign.id, record_type: "policy")

    assert_nil foreign.reload.package_id
  end

  test "the composition list annotates records held by another package" do
    sign_in @admin
    @record.update!(package: @pkg_b)

    get dashboard_pp_package_path(@pkg_a, record_type: "policy")

    assert_response :success
    assert_select "body", text: /Already in/
    # A committed record gets an explicit Re-assign action, never a checkbox.
    assert_select "form[action=?]", assign_record_dashboard_pp_package_path(@pkg_a, record_id: @record.id, record_type: "policy", reassign: true)
    assert_includes response.body, I18n.t("pp_records.packages.reassign")
  end

  test "the new and edit forms render" do
    sign_in @admin

    get new_dashboard_pp_package_path
    assert_response :success

    get edit_dashboard_pp_package_path(@pkg_a)
    assert_response :success
  end

  test "deleting a package keeps its records" do
    sign_in @admin
    @record.update!(package: @pkg_a)

    delete dashboard_pp_package_path(@pkg_a)

    assert PpRecord.exists?(@record.id)
    assert_nil @record.reload.package_id
  end
end
