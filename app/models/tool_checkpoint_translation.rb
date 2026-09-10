class ToolCheckpointTranslation < ApplicationRecord
  skip_activity_trail
  validates :tool_checkpoint_id, presence: true
  validates :language_code, presence: true, length: { maximum: 10 }
  validates :name, presence: true

  belongs_to :tool_checkpoint
  belongs_to :language, foreign_key: "language_code", primary_key: "code"

  scope :for_language, ->(code) { where(language_code: code) }

  after_save :update_last_modified_at
  after_save :mark_other_translations_for_review, if: :content_changed?

  private

  def update_last_modified_at
    return unless saved_change_to_name?

    update_column(:last_modified_at, Time.current) unless last_modified_at_changed?
    update_column(:needs_review, false) if needs_review
  end

  def content_changed?
    saved_change_to_name?
  end

  def mark_other_translations_for_review
    return if saved_change_to_id? || id_before_last_save.nil?

    was_needing_review = attribute_before_last_save(:needs_review)
    return if was_needing_review == true

    current_time = last_modified_at || Time.current
    tool_checkpoint.tool_checkpoint_translations
      .where.not(language_code: language_code)
      .where(needs_review: false)
      .update_all(
        needs_review: true,
        source_updated_at: current_time
      )
  end
end
