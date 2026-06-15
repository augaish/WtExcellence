class FixAiGeneratedReviewFlags < ActiveRecord::Migration[8.0]
  def up
    # Set needs_review to false for all AI-generated translations
    # that currently have needs_review: true
    ClauseTranslation.where(ai_generated: true, needs_review: true).update_all(needs_review: false)
    ChecklistItemTranslation.where(ai_generated: true, needs_review: true).update_all(needs_review: false)
  end

  def down
    # This migration is not reversible as we can't determine which records
    # should have needs_review: true
  end
end
