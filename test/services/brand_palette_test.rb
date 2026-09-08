require "test_helper"

class BrandPaletteTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Brand Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
  end

  test "a company that sets nothing gets the platform palette" do
    palette = @company.brand_palette

    assert_equal BrandPalette::DEFAULT_PRIMARY, palette.primary
    assert_equal BrandPalette::DEFAULT_ACCENT, palette.accent
    assert_not palette.primary_rejected?
  end

  test "the platform's own primary is readable with white text" do
    assert BrandPalette.readable_with_white?(BrandPalette::DEFAULT_PRIMARY)
  end

  test "a readable brand colour is used" do
    @company.update!(brand_primary_color: "#0B4F6C")

    assert_equal "#0B4F6C", @company.brand_palette.primary
    assert_not @company.brand_palette.primary_rejected?
  end

  test "a colour that white text cannot be read on is rejected, not applied" do
    @company.update!(brand_primary_color: "#FFFF00")
    palette = @company.brand_palette

    assert_equal BrandPalette::DEFAULT_PRIMARY, palette.primary
    assert palette.primary_rejected?, "the company should be told its colour was rejected"
  end

  test "a malformed colour is refused at the model" do
    @company.brand_primary_color = "purple"

    assert_not @company.valid?
    assert_predicate @company.errors[:brand_primary_color], :present?
  end

  test "reloading picks up a changed palette" do
    @company.update!(brand_primary_color: "#0B4F6C")
    assert_equal "#0B4F6C", @company.brand_palette.primary

    @company.update!(brand_primary_color: nil)
    assert_equal BrandPalette::DEFAULT_PRIMARY, @company.reload.brand_palette.primary
  end
end
