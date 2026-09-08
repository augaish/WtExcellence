require "test_helper"

class Dashboard::BrandingControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!

    @company = Company.create!(name: "Brand Co #{SecureRandom.hex(4)}", license_seats: 10, credits: 50, is_active: true)
    @admin = create_user("brand-admin", CompanyUser::ROLES[:company_admin])
    @contributor = create_user("brand-contrib", CompanyUser::ROLES[:company_contributor])
  end

  def create_user(prefix, role)
    user = User.create!(email: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123", password_confirmation: "password123", name: prefix, is_active: true)
    CompanyUser.create!(company: @company, user: user, role: role)
    user
  end

  test "a company admin can open the branding page" do
    sign_in @admin
    get dashboard_branding_path

    assert_response :success
    assert_select "input[name=?]", "company[brand_primary_color]"
  end

  test "a contributor cannot manage branding" do
    sign_in @contributor
    get dashboard_branding_path

    assert_redirected_to dashboard_overview_path
  end

  test "saving a readable colour applies it" do
    sign_in @admin
    patch dashboard_update_branding_path, params: { company: { brand_primary_color: "#0B4F6C" } }

    assert_redirected_to dashboard_branding_path
    assert_equal "#0B4F6C", @company.reload.brand_primary_color
    assert_equal "#0B4F6C", @company.brand_palette.primary
  end

  test "a colour white text cannot be read on is stored but not applied" do
    sign_in @admin
    patch dashboard_update_branding_path, params: { company: { brand_primary_color: "#FFFF00" } }

    @company.reload
    assert_equal BrandPalette::DEFAULT_PRIMARY, @company.brand_palette.primary
    assert @company.brand_palette.primary_rejected?

    get dashboard_branding_path
    assert_select "div", text: /#{Regexp.escape(I18n.t('branding.primary_rejected'))}/
  end

  test "a malformed colour is rejected with an error" do
    sign_in @admin
    patch dashboard_update_branding_path, params: { company: { brand_primary_color: "purple" } }

    assert_response :unprocessable_entity
    assert_nil @company.reload.brand_primary_color
  end

  test "the company logo renders beside the platform logo" do
    @company.brand_logo.attach(io: StringIO.new("logo-bytes"), filename: "logo.png", content_type: "image/png")
    sign_in @admin
    get dashboard_overview_path

    assert_response :success
    assert_select "nav img[alt=?]", @company.name
  end
end
