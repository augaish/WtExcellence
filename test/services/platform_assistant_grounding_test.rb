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

  test "a vendor question carries the assessment scores, rationale, sign-off state and evidence text" do
    company = Company.create!(name: "AI Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    user = User.create!(email: "ai-#{SecureRandom.hex(4)}@example.com", password: "Password1234",
      password_confirmation: "Password1234", name: "Assessor", is_active: true)
    CompanyUser.create!(company: company, user: user, role: CompanyUser::ROLES[:company_risk_manager])
    vendor = Vendor.create!(company: company, name: "Nimbus Hosting", created_by: user)
    assessment = vendor.assessments.create!(company: company, assessed_by: user, assessed_on: Date.current,
      scores: VendorAssessment::CRITERIA.index_with { 4 }, rationale: "Strong DR, weak exit plan")
    upload = Upload.new(company_id: company.id, filename: "dr.txt", name: "DR test report", mime_type: "text/plain",
      size_bytes: 10, uploaded_by: user.id, visibility: "public")
    upload.file.attach(io: StringIO.new("Failover completed in 42 minutes."), filename: "dr.txt", content_type: "text/plain")
    upload.save!
    EvidenceAttachment.create!(attachable: assessment, upload: upload)

    by_name = PlatformAssistantService.new(company, user: user).send(:gather_context, "How did nimbus score?")
    by_page = PlatformAssistantService.new(company, user: user, page_path: "/dashboard/vendors/#{vendor.id}")
      .send(:gather_context, "Summarise this supplier")

    [ by_name, by_page ].each do |context|
      text = context.map { |c| c[:text] }.join("\n")
      assert_includes text, "Strong DR, weak exit plan"
      assert_includes text, "continuity 4/5"
      assert_includes text, "awaiting sign-off"
      assert_includes text, "Failover completed in 42 minutes."
      assert_includes context.map { |c| c[:label] }, "Evidence: DR test report"
    end
  end
end
