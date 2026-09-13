# Hard-deletes a user and everything that is theirs alone. Returns the user's
# assigned credits to the company before removing their membership. Runs in a
# single transaction, so a failure leaves the user untouched.
#
# Two kinds of reference point at a user:
#   * rows that ARE the user's (a reviewer slot, a comment, a task, a holder
#     entry, a notification) — removed with them;
#   * rows that merely remember who acted (owner, creator, approver,
#     the person who did a stage transition) — kept, with the pointer cleared,
#     so a record never loses its history because its author left.
class UserDeletionService
  class CannotDeleteUserError < StandardError; end

  # Tables whose row belongs to the user: [model, column]
  OWN_ROWS = [
    [ "AssignmentEvaluation", :evaluator_id ],
    [ "AssessmentUser", :user_id ],
    [ "AuthorityMatrixReview", :user_id ],
    [ "AuthorityReviewComment", :user_id ],
    [ "AuthorityAssignment", :user_id ],
    [ "PpClauseComment", :user_id ],
    [ "PpStageAssignee", :user_id ],
    [ "PpStageTask", :user_id ],
    [ "Notification", :recipient_id ]
  ].freeze

  # Tables that remember the user as an actor: [model, column]
  ACTOR_POINTERS = [
    [ "AuditLog", :actor_user_id ],
    [ "AiInstruction", :created_by_id ],
    [ "AssessmentUser", :assigner_user_id ],
    [ "Assessment", :last_edited_by_user_id ],
    [ "AuthorityConsultation", :raised_by_id ],
    [ "AuthorityConsultation", :ruled_by_id ],
    [ "AuthorityDelegation", :grantor_approved_by_id ],
    [ "AuthorityDelegation", :revoked_by_id ],
    [ "AuthorityReviewComment", :replied_by_id ],
    [ "CapaAction", :created_by_id ],
    [ "CapaActivity", :performed_by_id ],
    [ "Capa", :created_by_id ],
    [ "CheckpointSummary", :last_edited_by_user_id ],
    [ "CompanyChecklistItemInstance", :assigned_to ],
    [ "CompanyChecklistItemInstance", :last_updated_by ],
    [ "CompanyStandardVersionHistory", :changed_by ],
    [ "CompanyStandard", :assigned_by ],
    [ "CustomerCommitment", :created_by_id ],
    [ "CustomerCommitment", :verified_by_id ],
    [ "Folder", :created_by ],
    [ "OrgUnit", :head_user_id ],
    [ "PpProcess", :owner_user_id ],
    [ "PpRecord", :owner_user_id ],
    [ "PpRecord", :verifier_user_id ],
    [ "PpStageApproval", :received_by_id ],
    [ "PpStageApproval", :requested_by_id ],
    [ "PpStageTransition", :actor_user_id ],
    [ "Risk", :accepted_by_id ],
    [ "Risk", :created_by_id ],
    [ "SlaMeasurement", :recorded_by_id ],
    [ "SlaMeasurement", :reviewed_by_id ],
    [ "User", :invited_by_id ],
    [ "VendorAssessment", :assessed_by_id ],
    [ "VendorAssessment", :reviewed_by_id ],
    [ "Vendor", :approved_by_id ],
    [ "Vendor", :created_by_id ]
  ].freeze

  def self.call(user)
    new(user).call
  end

  def initialize(user)
    @user = user
  end

  def call
    raise CannotDeleteUserError, "User is required" unless @user.is_a?(User)

    User.transaction do
      return_credits_to_company!
      destroy_company_user!
      delete_own_rows!
      clear_actor_pointers!
      @user.destroy!
    end

    true
  end

  private

  def return_credits_to_company!
    company_user = @user.company_user
    return unless company_user

    company = company_user.company
    credits_to_return = company_user.assigned_credits.to_i
    return if credits_to_return <= 0

    company.lock!
    company.update!(credits: company.credits + credits_to_return)
  end

  def destroy_company_user!
    @user.company_user&.destroy!
  end

  # Comments carry replies, so they go one by one; the rest go in one statement.
  def delete_own_rows!
    Comment.where(user_id: @user.id).find_each(&:destroy)
    OWN_ROWS.each { |model, column| model.constantize.where(column => @user.id).delete_all }
  end

  def clear_actor_pointers!
    ACTOR_POINTERS.each { |model, column| model.constantize.where(column => @user.id).update_all(column => nil) }
  end
end
