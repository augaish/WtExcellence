require "test_helper"

# A person who worked across the modules can still be removed: what was theirs
# alone goes with them, and what they touched keeps its history.
class UserDeletionServiceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Del Co #{SecureRandom.hex(4)}", license_seats: 5, credits: 10, is_active: true)
    @user = User.create!(email: "del-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Leaving", is_active: true)
    @admin = User.create!(email: "del-admin-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Admin", is_active: true)
    CompanyUser.create!(company: @company, user: @user, role: CompanyUser::ROLES[:company_quality_manager])
    CompanyUser.create!(company: @company, user: @admin, role: CompanyUser::ROLES[:company_admin])
  end

  test "a user with authorities, reviews, comments, records and stage work is deleted and the records stay" do
    unit = @company.org_units.create!(name_en: "Quality", level: 1, head_user: @user)
    matrix = AuthorityMatrixVersionService.first_version(@company, actor: @admin)
    authority = @company.authorities.create!(matrix: matrix, name_en: "Sign")
    authority.default_band.assignments.create!(level: "authorize", user: @user)
    matrix.matrix_reviews.create!(user: @user, requested_by: @admin, requested_at: Time.current)
    comment = matrix.review_comments.create!(authority: authority, user: @user, body: "Note")
    matrix.review_comments.create!(authority: authority, user: @admin, body: "Other", decision: "accepted", reply: "ok", replied_by: @user, replied_at: Time.current)
    record = @company.pp_records.create!(record_type: "policy", title_en: "Policy", description: "x", owner_user: @user, verifier_user: @user)
    invited = User.create!(email: "inv-#{SecureRandom.hex(4)}@example.com", password: "password123",
      password_confirmation: "password123", name: "Invited", is_active: false, invited_by: @user)
    Notification.create!(recipient: @user, kind: "authority_review_requested", title: "x", link_path: "/", payload: {})
    Thread.current[:current_user] = @user
    record.update!(title_en: "Policy 2")
    Thread.current[:current_user] = nil

    assert UserDeletionService.call(@user)

    assert_nil User.find_by(id: @user.id)
    assert_nil unit.reload.head_user_id
    assert_equal 0, authority.default_band.assignments.count
    assert_equal 0, matrix.matrix_reviews.count
    assert_nil AuthorityReviewComment.find_by(id: comment.id)
    assert_nil matrix.review_comments.find_by(user: @admin).replied_by_id
    record.reload
    assert_equal "Policy 2", record.title_en
    assert_nil record.owner_user_id
    assert_nil invited.reload.invited_by_id
    assert AuditLog.where(entity_id: record.id, actor_user_id: nil).exists?, "the trail is kept without the actor"
  end
end
