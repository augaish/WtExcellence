require "test_helper"

# F15 — asked how to link a risk to a vendor, the assistant proposed "Related
# Items", "Associations" and "Link Existing Risk" controls that do not exist,
# sending the user hunting for buttons that were never built.
class PlatformAssistantGroundingTest < ActiveSupport::TestCase
  test "the product map covers every module the product actually has" do
    module_keys = Company::MODULES.keys.map(&:to_s)
    mapped = PlatformAssistantService::PRODUCT_MAP.keys

    missing = module_keys - mapped
    assert_empty missing,
      "the assistant would have nothing true to say about: #{missing.join(', ')}"
  end

  test "the map does not describe modules that do not exist" do
    stray = PlatformAssistantService::PRODUCT_MAP.keys - Company::MODULES.keys.map(&:to_s)

    assert_empty stray, "the assistant would describe areas the product does not have: #{stray.join(', ')}"
  end

  test "every mapped area says something substantive" do
    PlatformAssistantService::PRODUCT_MAP.each do |key, description|
      assert_operator description.length, :>, 30, "#{key} has no useful description"
    end
  end
end
