require "test_helper"

# The logo is served by the app and previewed before saving.
class Dashboard::BrandingPreviewTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes!
    @company = Company.create!(name: "Brand #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @admin = User.create!(email: "brand-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Brand Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
    @viewer = User.create!(email: "brandv-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Viewer", is_active: true)
    CompanyUser.create!(company: @company, user: @viewer, role: CompanyUser::ROLES[:company_viewer])
    sign_in @admin
  end

  def png
    Rack::Test::UploadedFile.new(Rails.root.join("app/assets/images/logo.png"), "image/png")
  end

  test "the page previews the logo and colours live, through the app's own logo route" do
    get dashboard_branding_path
    assert_response :success
    assert_select "form[data-controller=brand-preview]"
    assert_select "input[type=file][data-action='change->brand-preview#logoChanged']"
    assert_select "img[data-brand-preview-target=logo]"

    patch dashboard_update_branding_path, params: { company: { brand_logo: png, brand_primary_color: "#123456" } }
    assert_redirected_to dashboard_branding_path
    follow_redirect!
    assert_select "img[data-brand-preview-target=logo][src=?]", dashboard_branding_logo_path
  end

  test "the logo route streams the file to any member and 404s when there is none" do
    get dashboard_branding_logo_path
    assert_response :not_found

    @company.brand_logo.attach(io: File.open(Rails.root.join("app/assets/images/logo.png")), filename: "logo.png", content_type: "image/png")
    sign_out @admin
    sign_in @viewer
    get dashboard_branding_logo_path
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_operator response.body.bytesize, :>, 100
  end

  test "the navbar and the document cover use the app route for the company logo" do
    @company.brand_logo.attach(io: File.open(Rails.root.join("app/assets/images/logo.png")), filename: "logo.png", content_type: "image/png")
    get dashboard_overview_path
    assert_select "img[src=?]", dashboard_branding_logo_path

    record = @company.pp_records.create!(record_type: "policy", title_en: "Policy")
    get document_dashboard_pp_record_path(record)
    assert_select "img[src=?]", dashboard_branding_logo_path
  end
end
