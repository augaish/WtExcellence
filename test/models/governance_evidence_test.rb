require "test_helper"

# The review found a risk closed and a commitment fulfilled with no evidence at
# all, because governance records could not carry any.
class GovernanceEvidenceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Ev Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @user = User.create!(email: "ev-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Owner", is_active: true)

    @upload = Upload.new(company: @company, name: "Recovery test report", uploaded_by: @user.id,
      visibility: "public", filename: "report.pdf", mime_type: "application/pdf", size_bytes: 20)
    @upload.file.attach(io: StringIO.new("evidence"), filename: "report.pdf", content_type: "application/pdf")
    @upload.save!
  end

  test "each governance record can carry evidence" do
    records = {
      @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4) => "Supplier outage",
      @company.vendors.create!(name: "Cloud Co") => "Cloud Co",
      @company.customer_commitments.create!(title: "Monthly report", customer_name: "Ministry") => "Monthly report"
    }

    records.each do |record, expected_name|
      attachment = EvidenceAttachment.create!(upload: @upload, attachable: record, attached_by: @user.id)

      assert_equal [ @upload ], record.reload.uploads.to_a
      assert_equal expected_name, attachment.attachable_name,
        "#{record.class} evidence should name the record, not report Unknown"
    end
  end

  test "governance evidence can be listed on its own" do
    risk = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4)
    EvidenceAttachment.create!(upload: @upload, attachable: risk, attached_by: @user.id)

    assert_equal 1, EvidenceAttachment.for_governance.count
  end

  test "one document supports several governance records" do
    risk = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4)
    vendor = @company.vendors.create!(name: "Cloud Co")

    EvidenceAttachment.create!(upload: @upload, attachable: risk, attached_by: @user.id)
    EvidenceAttachment.create!(upload: @upload, attachable: vendor, attached_by: @user.id)

    assert_equal 2, @upload.evidence_attachments.count
  end

  test "the same document cannot be linked twice to one record" do
    risk = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4)
    EvidenceAttachment.create!(upload: @upload, attachable: risk, attached_by: @user.id)

    duplicate = EvidenceAttachment.new(upload: @upload, attachable: risk, attached_by: @user.id)
    assert_not duplicate.valid?
  end

  test "deleting a record takes its evidence links with it, not the document" do
    risk = @company.risks.create!(title: "Supplier outage", likelihood: 3, impact: 4)
    EvidenceAttachment.create!(upload: @upload, attachable: risk, attached_by: @user.id)

    risk.destroy
    assert_equal 0, EvidenceAttachment.where(attachable_type: "Risk").count
    assert Upload.exists?(@upload.id), "the document itself must survive"
  end
end
