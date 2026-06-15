# One-time data migration: hard-delete all users that are currently soft-deleted (deleted_at present).
# Uses UserDeletionService so credits are returned to the company and all related data is cleaned up.
class HardDeleteSoftDeletedUsers < ActiveRecord::Migration[7.1]
  def up
    soft_deleted = User.unscoped.where.not(deleted_at: nil)
    total = soft_deleted.count
    return if total.zero?

    say "Found #{total} soft-deleted user(s). Hard-deleting..."

    deleted_count = 0
    failed = []

    soft_deleted.find_each do |user|
      UserDeletionService.call(user)
      deleted_count += 1
      say "  Hard-deleted user #{user.id} (#{user.email})", true
    rescue => e
      failed << { id: user.id, email: user.email, error: e.message }
      say "  Skipped user #{user.id} (#{user.email}): #{e.message}", true
    end

    say "Hard-deleted #{deleted_count} user(s)."
    if failed.any?
      say "Failed #{failed.size} user(s):", true
      failed.each { |f| say "  - #{f[:id]} #{f[:email]}: #{f[:error]}", true }
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Hard-deleted users cannot be restored."
  end
end
