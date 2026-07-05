require "test_helper"

class TrustCenterControllerTest < ActionDispatch::IntegrationTest
  setup do
    @enabled = Company.create!(
      name: "Trust Enabled #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true,
      trust_center_enabled: true
    )
    @disabled = Company.create!(
      name: "Trust Disabled #{SecureRandom.hex(4)}",
      license_seats: 5,
      is_active: true,
      trust_center_enabled: false
    )
  end

  test "public can view an enabled company's trust center without auth" do
    get trust_center_path(@enabled)

    assert_response :success
    assert_match @enabled.name, @response.body
  end

  test "disabled company's trust center returns 404" do
    get trust_center_path(@disabled)

    assert_response :not_found
  end

  test "unknown company id returns 404" do
    get trust_center_path("00000000-0000-0000-0000-000000000000")

    assert_response :not_found
  end
end
