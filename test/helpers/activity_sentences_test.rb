require "test_helper"

# The trail reads in words: names for changed references, labels for statuses.
class ActivitySentencesTest < ActionView::TestCase
  include GovernanceActivityHelper

  setup do
    @company = Company.create!(name: "Words Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @a = User.create!(email: "a-#{SecureRandom.hex(4)}@example.com", password: "Password1234", password_confirmation: "Password1234", name: "Amal Owner", is_active: true)
    @b = User.create!(email: "b-#{SecureRandom.hex(4)}@example.com", password: "Password1234", password_confirmation: "Password1234", name: "Badr Owner", is_active: true)
    @ma = CompanyUser.create!(company: @company, user: @a, role: CompanyUser::ROLES[:company_admin])
    @mb = CompanyUser.create!(company: @company, user: @b, role: CompanyUser::ROLES[:company_viewer])
  end

  def entry(entity_type, changes)
    AuditLog.new(entity_type: entity_type, action: "UPDATE_#{entity_type.upcase}", payload_json: { "changes" => changes })
  end

  test "a changed owner shows both names, not ids" do
    sentence = activity_change_sentences(entry("vendor", { "owner_id" => [ @ma.id, @mb.id ] })).sole
    assert_includes sentence, "Amal Owner"
    assert_includes sentence, "Badr Owner"
    refute_match(/[0-9a-f]{8}-[0-9a-f]{4}/, sentence)
  end

  test "a status shows its label, and a removed reference says so" do
    sentence = activity_change_sentences(entry("vendor", { "approval_status" => [ "not_approved", "approved" ] })).sole
    assert_includes sentence, I18n.t("vendor_assessment.approval_statuses.not_approved")
    assert_includes sentence, I18n.t("vendor_assessment.approval_statuses.approved")
    refute_includes sentence, "not_approved"

    gone = activity_change_sentences(entry("risk", { "control_owner_id" => [ SecureRandom.uuid, nil ] })).sole
    assert_includes gone, I18n.t("governance_activity.removed_record")
    assert_includes gone, I18n.t("governance_activity.not_set")

    generic = activity_change_sentences(entry("pp_record", { "record_type" => [ "policy", "procedure" ] })).sole
    assert_includes generic, "Policy"
  end
end
