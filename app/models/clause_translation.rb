class ClauseTranslation < ApplicationRecord
  # Validations
  validates :clause_id, presence: true
  validates :language_code, presence: true, length: { maximum: 10 }
  validates :title, presence: true, length: { maximum: 500 }

  # Associations
  belongs_to :clause
  belongs_to :language, foreign_key: "language_code", primary_key: "code"

  # Scopes
  scope :for_language, ->(code) { where(language_code: code) }

  # Callbacks to update search index when translations change
  after_save :reindex_clause
  after_destroy :reindex_clause
  after_save :update_last_modified_at
  after_save :mark_other_translations_for_review, if: :content_changed?

  private

  def reindex_clause
    # Touch the clause to trigger its save callback, which will automatically
    # update the pg_search index since searchable_content is recalculated
    clause&.touch
  end

  def update_last_modified_at
    # Update last_modified_at when translation content changes
    if saved_change_to_title? || saved_change_to_summary? || saved_change_to_body?
      update_column(:last_modified_at, Time.current) unless last_modified_at_changed?
      # Clear needs_review flag when translation is updated (user is fixing it)
      update_column(:needs_review, false) if needs_review
    end
  end

  def content_changed?
    saved_change_to_title? || saved_change_to_summary? || saved_change_to_body?
  end

  def mark_other_translations_for_review
    # Don't mark others for review if this is a new record (just created)
    # Only mark when updating an existing translation
    return if saved_change_to_id? || id_before_last_save.nil?

    # If this translation already needed review before this save, don't propagate to other languages
    # (user is fixing an outdated translation, not creating new changes)
    was_needing_review = attribute_before_last_save(:needs_review)
    return if was_needing_review == true

    current_locale = language_code
    current_time = last_modified_at || Time.current

    # Mark all other translations as needing review
    # Only mark translations that don't already need review (auto-translated ones with needs_review: false)
    clause.clause_translations
      .where.not(language_code: current_locale)
      .where(needs_review: false)
      .update_all(
        needs_review: true,
        source_updated_at: current_time
      )
  end
end
