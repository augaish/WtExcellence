# Hard-deletes a user and all related data. Returns the user's assigned credits to the company
# before removing their company membership. Runs in a single transaction.
class UserDeletionService
  class CannotDeleteUserError < StandardError; end

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
      delete_user_dependent_records!
      nullify_optional_user_references!
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

  def delete_user_dependent_records!
    # Records with required FK to user that User model does not declare (no dependent)
    AssignmentEvaluation.where(evaluator_id: @user.id).delete_all
    # Comments: user_id is required (FK); destroy all comments by this user so the user can be deleted.
    # Uses find_each + destroy so dependent: :destroy on Comment (replies) is respected.
    Comment.where(user_id: @user.id).find_each(&:destroy)
  end

  def nullify_optional_user_references!
    AuditLog.where(actor_user_id: @user.id).update_all(actor_user_id: nil)
    CapaActivity.where(performed_by_id: @user.id).update_all(performed_by_id: nil)
    Capa.where(created_by_id: @user.id).update_all(created_by_id: nil)
    AssessmentUser.where(assigner_user_id: @user.id).update_all(assigner_user_id: nil)
    Assessment.where(last_edited_by_user_id: @user.id).update_all(last_edited_by_user_id: nil)
    Folder.where(created_by: @user.id).update_all(created_by: nil)
  end
end
